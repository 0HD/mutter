# Patches the user's libmumble checkout in place. Idempotent: re-running on
# an already-patched tree is a no-op.
#
# The three changes:
#
#   1. include/mumble/Key.hpp: add a missing <string> include. The newer MSVC
#      STL no longer pulls it in transitively via <string_view>, so the
#      `std::string pem() const` declaration fails to parse.
#
#   2. cmake/setup_dependencies.cmake: drop GIT_SHALLOW on the quickpool
#      FetchContent_Declare. Shallow git clones can't reach a specific commit
#      hash that isn't at a branch tip, which is exactly the pinned commit.
#
#   3. src/Pack.cpp: rewrite the UserState case in the TCP message serializer
#      so it only sets protobuf fields the caller actually populated. The
#      upstream version sends every default sentinel (UINT32_MAX for IDs,
#      empty strings, all admin booleans), which Mumble servers reject with
#      PermissionDenied on every self-state update.
#
# All three are real bug fixes against current libmumble and worth upstreaming.

$ErrorActionPreference = 'Continue'

$libmumble = (Resolve-Path "$PSScriptRoot\..\third_party\libmumble").Path
if (-not (Test-Path "$libmumble\CMakeLists.txt")) {
    throw "libmumble submodule not initialized at $libmumble. Run: git submodule update --init --recursive"
}

function Update-FileText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$Transform
    )
    $original = [System.IO.File]::ReadAllText($Path)
    $hadCrlf  = $original.Contains("`r`n")
    $norm     = $original -replace "`r`n", "`n"
    $updated  = & $Transform $norm
    if ($null -eq $updated -or $updated -eq $norm) { return $false }
    if ($hadCrlf) { $updated = $updated -replace "`n", "`r`n" }
    [System.IO.File]::WriteAllText($Path, $updated)
    return $true
}

# Patch 1: add <string> include to Key.hpp
$keyHpp = Join-Path $libmumble 'include\mumble\Key.hpp'
$changed = Update-FileText -Path $keyHpp -Transform {
    param($c)
    if ($c -match '(?m)^#include <string>$') { return $null }
    return ($c -replace '(#include <memory>)(\n)(#include <string_view>)', "`$1`$2#include <string>`$2`$3")
}
if ($changed) { Write-Host 'patched include/mumble/Key.hpp' -ForegroundColor Cyan }

# Patch 2: remove GIT_SHALLOW from the quickpool FetchContent block
$setupDeps = Join-Path $libmumble 'cmake\setup_dependencies.cmake'
$changed = Update-FileText -Path $setupDeps -Transform {
    param($c)
    return ($c -replace '(GIT_TAG\s+ddc415bec1fc624e1c6b21c1b47063ca2eef84de\n)\s*GIT_SHALLOW\s+ON\n', '$1')
}
if ($changed) { Write-Host 'patched cmake/setup_dependencies.cmake' -ForegroundColor Cyan }

# Patch 3: rewrite the UserState case in Pack.cpp's TCP serializer, and add
# the <limits> include needed by std::numeric_limits.
$packCpp = Join-Path $libmumble 'src\Pack.cpp'

$packOldBlock = @'
			MumbleTCP::UserState proto;
			proto.set_session(msg.session);
			proto.set_actor(msg.actor);
			proto.set_name(msg.name);
			if (msg.userID) {
				proto.set_user_id(msg.userID.value());
			}
			proto.set_channel_id(msg.channelID);
			proto.set_mute(msg.mute);
			proto.set_deaf(msg.deaf);
			proto.set_suppress(msg.suppress);
			proto.set_self_mute(msg.selfMute);
			proto.set_self_deaf(msg.selfDeaf);
			proto.set_texture(msg.texture.data(), msg.texture.size());
			proto.set_plugin_context(msg.pluginContext.data(), msg.pluginContext.size());
			proto.set_plugin_identity(msg.pluginIdentity);
			proto.set_comment(msg.comment);
			proto.set_hash(msg.hash);
			proto.set_comment_hash(msg.commentHash.data(), msg.commentHash.size());
			proto.set_texture_hash(msg.textureHash.data(), msg.textureHash.size());
			proto.set_priority_speaker(msg.prioritySpeaker);
			proto.set_recording(msg.recording);
'@

$packNewBlock = @'
			// Only serialize UserState fields the caller actually wants to
			// update. Defaults (UINT32_MAX for IDs, empty for strings, false
			// for admin booleans) are sentinels meaning "unset"; sending
			// them makes the server interpret them as real updates and reply
			// with PermissionDenied. self_mute / self_deaf are always sent
			// because false is action-meaningful (= unmute).
			MumbleTCP::UserState proto;
			if (msg.session != std::numeric_limits< uint32_t >::max())   proto.set_session(msg.session);
			if (msg.actor   != std::numeric_limits< uint32_t >::max())   proto.set_actor(msg.actor);
			if (!msg.name.empty())                                       proto.set_name(msg.name);
			if (msg.userID)                                              proto.set_user_id(msg.userID.value());
			if (msg.channelID != std::numeric_limits< uint32_t >::max()) proto.set_channel_id(msg.channelID);
			if (msg.mute)                                                proto.set_mute(true);
			if (msg.deaf)                                                proto.set_deaf(true);
			if (msg.suppress)                                            proto.set_suppress(true);
			proto.set_self_mute(msg.selfMute);
			proto.set_self_deaf(msg.selfDeaf);
			if (!msg.texture.empty())        proto.set_texture(msg.texture.data(), msg.texture.size());
			if (!msg.pluginContext.empty())  proto.set_plugin_context(msg.pluginContext.data(), msg.pluginContext.size());
			if (!msg.pluginIdentity.empty()) proto.set_plugin_identity(msg.pluginIdentity);
			if (!msg.comment.empty())        proto.set_comment(msg.comment);
			if (!msg.hash.empty())           proto.set_hash(msg.hash);
			if (!msg.commentHash.empty())    proto.set_comment_hash(msg.commentHash.data(), msg.commentHash.size());
			if (!msg.textureHash.empty())    proto.set_texture_hash(msg.textureHash.data(), msg.textureHash.size());
			if (msg.prioritySpeaker)         proto.set_priority_speaker(true);
			if (msg.recording)               proto.set_recording(true);
'@

# Normalize the here-strings to LF for byte-exact matching.
$packOldBlock = $packOldBlock -replace "`r`n", "`n"
$packNewBlock = $packNewBlock -replace "`r`n", "`n"

$changed = Update-FileText -Path $packCpp -Transform {
    param($c)
    if (-not $c.Contains($packOldBlock)) { return $null }
    $out = $c.Replace($packOldBlock, $packNewBlock)
    if ($out -notmatch '(?m)^#include <limits>$') {
        $out = $out -replace '(#include <cstring>\n)', "`$1#include <limits>`n"
    }
    return $out
}
if ($changed) { Write-Host 'patched src/Pack.cpp' -ForegroundColor Cyan }
