# mutter

A Mumble client written in Flutter, for Windows. Work in progress.

## TODO

- push-to-talk and VAD
- noise suppression
- per-user volume sliders
- global hotkeys, system tray
- recording
- whisper / shout
- screenshare

## Build instructions

Requires:

- Visual Studio 2022 with the C++ workload
- Flutter 3.35+
- `nuget.exe` on PATH (`winget install -e --id Microsoft.NuGet`)
- Windows Developer Mode enabled

Clone with submodules (libmumble is a submodule under `third_party/`):

```powershell
git clone --recurse-submodules https://github.com/0HD/mutter.git
# or, on an existing clone:
git submodule update --init --recursive
```

Then build:

```powershell
pwsh scripts/build_libmumble.ps1
pwsh scripts/build_native.ps1
cd app
flutter run -d windows
```

`build_libmumble.ps1` applies three in-place patches to libmumble (see
`scripts/apply_libmumble_patches.ps1`): a missing `<string>` include, a
FetchContent issue with shallow clones, and a UserState serializer bug that
makes Mumble servers reject every self-mute.

## How it works

The Flutter app talks to a C-ABI bridge DLL via `dart:ffi`. The bridge wraps
libmumble for the Mumble protocol and runs WASAPI capture/render threads for
audio, encoding/decoding with Opus. Protocol events come back to the Dart
isolate as JSON strings posted to a SendPort via the Dart Native API.
