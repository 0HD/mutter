# Patches the user's libmumble checkout in place. Idempotent: re-running on
# an already-patched tree is a no-op.
#
# Four changes:
#
#   1. include/mumble/Key.hpp: add a missing <string> include. The newer MSVC
#      STL no longer pulls it in transitively via <string_view>, so the
#      `std::string pem() const` declaration fails to parse.
#
#   2. cmake/setup_dependencies.cmake: drop GIT_SHALLOW on the quickpool
#      FetchContent_Declare. Shallow git clones can't reach a specific commit
#      hash that isn't at a branch tip, which is exactly the pinned commit.
#
#   3. src/Pack.cpp serialize: only set UserState fields the caller actually
#      populated, otherwise Mumble servers reject the message with
#      PermissionDenied (e.g. channel_id = UINT32_MAX is read as "move me to
#      channel UINT32_MAX").
#
#   4. include/mumble/Message.hpp + src/Pack.cpp deserialize: store the
#      UserState boolean state fields as std::optional<bool> instead of plain
#      bool, and respect protobuf's has_X() on parse. Without this, a server-
#      sent delta (say, "recording=true") arrives with all other booleans
#      defaulting to false, which the client reads as "the user just unmuted
#      and undeafened" and clears their status icons.
#
# All four are real bug fixes worth upstreaming.

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
if ($changed) { Write-Host 'patched src/Pack.cpp (UserState serializer)' -ForegroundColor Cyan }

# Patch 4a: store UserState bools as optional<bool> in the public Message struct.
$messageHpp = Join-Path $libmumble 'include\mumble\Message.hpp'

$userStateBoolOld = @'
		uint32_t channelID                               = UINT32_MAX;
		bool mute                                        = false;
		bool deaf                                        = false;
		bool suppress                                    = false;
		bool selfMute                                    = false;
		bool selfDeaf                                    = false;
'@ -replace "`r`n", "`n"

$userStateBoolNew = @'
		uint32_t channelID                               = UINT32_MAX;
		std::optional< bool > mute                       = {};
		std::optional< bool > deaf                       = {};
		std::optional< bool > suppress                   = {};
		std::optional< bool > selfMute                   = {};
		std::optional< bool > selfDeaf                   = {};
'@ -replace "`r`n", "`n"

$prsRecOld = @'
		bool prioritySpeaker                             = false;
		bool recording                                   = false;
'@ -replace "`r`n", "`n"

$prsRecNew = @'
		std::optional< bool > prioritySpeaker            = {};
		std::optional< bool > recording                  = {};
'@ -replace "`r`n", "`n"

$changed = Update-FileText -Path $messageHpp -Transform {
    param($c)
    $changed = $false
    if ($c.Contains($userStateBoolOld)) {
        $c = $c.Replace($userStateBoolOld, $userStateBoolNew)
        $changed = $true
    }
    if ($c.Contains($prsRecOld)) {
        $c = $c.Replace($prsRecOld, $prsRecNew)
        $changed = $true
    }
    if ($changed) { return $c } else { return $null }
}
if ($changed) { Write-Host 'patched include/mumble/Message.hpp (UserState optionals)' -ForegroundColor Cyan }

# Patch 4b: serialize uses has_value(); deserialize uses proto.has_X().
$packSerOldB = @'
			proto.set_self_mute(msg.selfMute);
			proto.set_self_deaf(msg.selfDeaf);
'@ -replace "`r`n", "`n"

$packSerNewB = @'
			if (msg.selfMute.has_value())  proto.set_self_mute(*msg.selfMute);
			if (msg.selfDeaf.has_value())  proto.set_self_deaf(*msg.selfDeaf);
'@ -replace "`r`n", "`n"

$packSerOldC = @'
			if (msg.mute)                                                proto.set_mute(true);
			if (msg.deaf)                                                proto.set_deaf(true);
			if (msg.suppress)                                            proto.set_suppress(true);
'@ -replace "`r`n", "`n"

$packSerNewC = @'
			if (msg.mute.has_value())      proto.set_mute(*msg.mute);
			if (msg.deaf.has_value())      proto.set_deaf(*msg.deaf);
			if (msg.suppress.has_value())  proto.set_suppress(*msg.suppress);
'@ -replace "`r`n", "`n"

$packSerOldD = @'
			if (msg.prioritySpeaker)         proto.set_priority_speaker(true);
			if (msg.recording)               proto.set_recording(true);
'@ -replace "`r`n", "`n"

$packSerNewD = @'
			if (msg.prioritySpeaker.has_value()) proto.set_priority_speaker(*msg.prioritySpeaker);
			if (msg.recording.has_value())       proto.set_recording(*msg.recording);
'@ -replace "`r`n", "`n"

$packDesOldA = @'
			msg.channelID = proto.channel_id();
			msg.mute      = proto.mute();
			msg.deaf      = proto.deaf();
			msg.suppress  = proto.suppress();
			msg.selfMute  = proto.self_mute();
			msg.selfDeaf  = proto.self_deaf();
'@ -replace "`r`n", "`n"

$packDesNewA = @'
			msg.channelID = proto.channel_id();
			if (proto.has_mute())      msg.mute      = proto.mute();      else msg.mute.reset();
			if (proto.has_deaf())      msg.deaf      = proto.deaf();      else msg.deaf.reset();
			if (proto.has_suppress())  msg.suppress  = proto.suppress();  else msg.suppress.reset();
			if (proto.has_self_mute()) msg.selfMute  = proto.self_mute(); else msg.selfMute.reset();
			if (proto.has_self_deaf()) msg.selfDeaf  = proto.self_deaf(); else msg.selfDeaf.reset();
'@ -replace "`r`n", "`n"

$packDesOldB = @'
			msg.prioritySpeaker = proto.priority_speaker();
			msg.recording       = proto.recording();
'@ -replace "`r`n", "`n"

$packDesNewB = @'
			if (proto.has_priority_speaker()) msg.prioritySpeaker = proto.priority_speaker(); else msg.prioritySpeaker.reset();
			if (proto.has_recording())        msg.recording       = proto.recording();        else msg.recording.reset();
'@ -replace "`r`n", "`n"

$changed = Update-FileText -Path $packCpp -Transform {
    param($c)
    $changed = $false
    foreach ($pair in @(
        @($packSerOldB, $packSerNewB),
        @($packSerOldC, $packSerNewC),
        @($packSerOldD, $packSerNewD),
        @($packDesOldA, $packDesNewA),
        @($packDesOldB, $packDesNewB)
    )) {
        if ($c.Contains($pair[0])) {
            $c = $c.Replace($pair[0], $pair[1])
            $changed = $true
        }
    }
    if ($changed) { return $c } else { return $null }
}
if ($changed) { Write-Host 'patched src/Pack.cpp (UserState optionals)' -ForegroundColor Cyan }
