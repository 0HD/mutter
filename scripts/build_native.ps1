# Builds the native bridge DLL (mumble_bridge.dll) and copies it next to the
# Flutter app's runner executable so `flutter run` can load it.
#
# Prereqs:
#   - libmumble-master has already been built (see scripts/build_libmumble.ps1).
#   - Visual Studio 2022 Community with the C++ workload is installed.

# Don't use 'Stop' — CMake writes warnings to stderr which PowerShell would
# wrongly treat as errors. We check $LASTEXITCODE explicitly instead.
$ErrorActionPreference = 'Continue'

$root        = Split-Path -Parent $PSScriptRoot
$nativeDir   = Join-Path $root 'native'
$nativeBuild = Join-Path $nativeDir 'build'
$appDir      = Join-Path $root 'app'
$vsRoot      = & 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' `
                  -latest -property installationPath
if (-not $vsRoot) { throw 'Visual Studio 2022 not found' }

$cmake  = Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$vcpkg  = Join-Path $vsRoot 'VC\vcpkg\scripts\buildsystems\vcpkg.cmake'

Write-Host 'Configuring native bridge…' -ForegroundColor Cyan
& $cmake -S $nativeDir -B $nativeBuild `
    -G 'Visual Studio 17 2022' -A x64 `
    "-DCMAKE_TOOLCHAIN_FILE=$vcpkg"
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }

Write-Host 'Building native bridge (Release)…' -ForegroundColor Cyan
& $cmake --build $nativeBuild --config Release -j
if ($LASTEXITCODE -ne 0) { throw 'CMake build failed' }

# Copy the bridge DLL (and libmumble + transitive deps) next to the Flutter
# Windows binary so the runtime loader finds them.
$dlls = @(
    'mumble_bridge.dll',
    'mumble_library.dll',
    'boost_thread-vc143-mt-x64-1_84.dll',
    'libcrypto-3-x64.dll',
    'libssl-3-x64.dll',
    'libprotobuf.dll',
    'opus.dll'
)

foreach ($flavor in 'Debug', 'Release') {
    $out = Join-Path $appDir "build\windows\x64\runner\$flavor"
    if (-not (Test-Path $out)) { continue }
    foreach ($dll in $dlls) {
        Copy-Item -Force (Join-Path $nativeBuild "Release\$dll") $out
    }
}

Write-Host 'Done. Run: flutter run -d windows' -ForegroundColor Green
