# Builds libmumble (Release, x64 shared) so the bridge can link against it.
# Run this once after cloning; rerun only if libmumble sources change.

$ErrorActionPreference = 'Continue'

$libmumble = Join-Path (Split-Path -Parent $PSScriptRoot) 'third_party\libmumble'
if (-not (Test-Path (Join-Path $libmumble 'CMakeLists.txt'))) {
    throw "libmumble submodule not initialized. Run: git submodule update --init --recursive"
}

# Apply our overlay patches (Key.hpp <string> include, quickpool GIT_SHALLOW
# removal, UserState serializer fix). See patches/libmumble/ and
# apply_libmumble_patches.ps1 for what each one does.
# $LASTEXITCODE isn't set by pure PowerShell scripts so we can't check it
# here — apply_libmumble_patches.ps1 throws on real errors itself.
& "$PSScriptRoot\apply_libmumble_patches.ps1"

$vsRoot = & 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' `
              -latest -property installationPath
$cmake  = Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$vcpkg  = Join-Path $vsRoot 'VC\vcpkg\scripts\buildsystems\vcpkg.cmake'

Write-Host 'Configuring libmumble' -ForegroundColor Cyan
& $cmake -S $libmumble -B (Join-Path $libmumble 'build') `
    -G 'Visual Studio 17 2022' -A x64 `
    "-DCMAKE_TOOLCHAIN_FILE=$vcpkg" `
    -DLIBMUMBLE_BUILD_TESTS=OFF `
    -DLIBMUMBLE_BUILD_EXAMPLES=OFF
if ($LASTEXITCODE -ne 0) { throw 'libmumble configure failed' }

Write-Host 'Building libmumble (Release)' -ForegroundColor Cyan
& $cmake --build (Join-Path $libmumble 'build') --config Release -j
if ($LASTEXITCODE -ne 0) { throw 'libmumble build failed' }

Write-Host 'libmumble built successfully.' -ForegroundColor Green
