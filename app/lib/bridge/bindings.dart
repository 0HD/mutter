// Dart FFI bindings for mumble_bridge.dll.
//
// This file mirrors native/include/mumble_bridge.h. Keep them in sync.

// ignore_for_file: library_private_types_in_public_api

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const String _libName = 'mumble_bridge';

DynamicLibrary _open() {
  if (Platform.isWindows) return DynamicLibrary.open('$_libName.dll');
  throw UnsupportedError('mutter is Windows-only.');
}

final DynamicLibrary _lib = _open();

// ---------------------------------------------------------------------------
// Native struct: mb_connect_params
// ---------------------------------------------------------------------------

final class MbConnectParams extends Struct {
  external Pointer<Utf8> host;
  @Uint16()
  external int port;
  external Pointer<Utf8> username;
  external Pointer<Utf8> password;
  external Pointer<Utf8> certPem;
  external Pointer<Utf8> keyPem;
  external Pointer<Pointer<Utf8>> tokens;
}

// ---------------------------------------------------------------------------
// Function signature typedefs
// ---------------------------------------------------------------------------

typedef _MbInitC = Int32 Function();
typedef _MbInitDart = int Function();

typedef _MbShutdownC = Void Function();
typedef _MbShutdownDart = void Function();

typedef _MbVersionC = Pointer<Utf8> Function();
typedef _MbVersionDart = Pointer<Utf8> Function();

typedef _MbSetEventPortC = Void Function(Int64);
typedef _MbSetEventPortDart = void Function(int);

typedef _MbInitDartApiC = Int32 Function(Pointer<Void>);
typedef _MbInitDartApiDart = int Function(Pointer<Void>);

typedef _MbConnectC = Int32 Function(Pointer<MbConnectParams>);
typedef _MbConnectDart = int Function(Pointer<MbConnectParams>);

typedef _MbDisconnectC = Void Function();
typedef _MbDisconnectDart = void Function();

typedef _MbJoinChannelC = Void Function(Uint32);
typedef _MbJoinChannelDart = void Function(int);

typedef _MbSendTextChannelC = Void Function(Uint32, Bool, Pointer<Utf8>);
typedef _MbSendTextChannelDart = void Function(int, bool, Pointer<Utf8>);

typedef _MbSendTextUserC = Void Function(Uint32, Pointer<Utf8>);
typedef _MbSendTextUserDart = void Function(int, Pointer<Utf8>);

typedef _MbSetBoolC = Void Function(Bool);
typedef _MbSetBoolDart = void Function(bool);

typedef _MbSetUint32C = Void Function(Uint32);
typedef _MbSetUint32Dart = void Function(int);

typedef _MbSetFloatC = Void Function(Float);
typedef _MbSetFloatDart = void Function(double);

typedef _MbSetStringC = Void Function(Pointer<Utf8>);
typedef _MbSetStringDart = void Function(Pointer<Utf8>);

typedef _MbSetTxModeC = Void Function(Int32);
typedef _MbSetTxModeDart = void Function(int);

typedef _MbReturnStringC = Pointer<Utf8> Function();
typedef _MbReturnStringDart = Pointer<Utf8> Function();

typedef _MbSetDeviceC = Int32 Function(Pointer<Utf8>);
typedef _MbSetDeviceDart = int Function(Pointer<Utf8>);

typedef _MbSetUserGainC = Void Function(Uint32, Float);
typedef _MbSetUserGainDart = void Function(int, double);

typedef _MbVoiceTargetAddUsersC =
    Void Function(Uint8, Pointer<Uint32>, IntPtr);
typedef _MbVoiceTargetAddUsersDart =
    void Function(int, Pointer<Uint32>, int);

typedef _MbVoiceTargetAddChannelC =
    Void Function(Uint8, Uint32, Bool, Bool);
typedef _MbVoiceTargetAddChannelDart =
    void Function(int, int, bool, bool);

typedef _MbVoiceTargetByteC = Void Function(Uint8);
typedef _MbVoiceTargetByteDart = void Function(int);

typedef _MbRecordingStartC = Int32 Function(Pointer<Utf8>, Int32, Int32);
typedef _MbRecordingStartDart = int Function(Pointer<Utf8>, int, int);

typedef _MbBoolReturnC = Bool Function();
typedef _MbBoolReturnDart = bool Function();

typedef _MbGenCertC = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>);
typedef _MbGenCertDart = int Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>);

typedef _MbFreeStringC = Void Function(Pointer<Utf8>);
typedef _MbFreeStringDart = void Function(Pointer<Utf8>);

// ---------------------------------------------------------------------------
// Resolved function pointers
// ---------------------------------------------------------------------------

final _MbInitDart mbInit =
    _lib.lookupFunction<_MbInitC, _MbInitDart>('mb_init');

final _MbShutdownDart mbShutdown =
    _lib.lookupFunction<_MbShutdownC, _MbShutdownDart>('mb_shutdown');

final _MbVersionDart _mbVersionPtr =
    _lib.lookupFunction<_MbVersionC, _MbVersionDart>('mb_version');
String mbVersion() => _mbVersionPtr().toDartString();

final _MbSetEventPortDart mbSetEventPort =
    _lib.lookupFunction<_MbSetEventPortC, _MbSetEventPortDart>('mb_set_event_port');

final _MbInitDartApiDart mbInitDartApi =
    _lib.lookupFunction<_MbInitDartApiC, _MbInitDartApiDart>('mb_init_dart_api');

final _MbConnectDart mbConnect =
    _lib.lookupFunction<_MbConnectC, _MbConnectDart>('mb_connect');

final _MbDisconnectDart mbDisconnect =
    _lib.lookupFunction<_MbDisconnectC, _MbDisconnectDart>('mb_disconnect');

final _MbJoinChannelDart mbJoinChannel =
    _lib.lookupFunction<_MbJoinChannelC, _MbJoinChannelDart>('mb_join_channel');

final _MbSendTextChannelDart mbSendTextChannel =
    _lib.lookupFunction<_MbSendTextChannelC, _MbSendTextChannelDart>(
        'mb_send_text_channel');

final _MbSendTextUserDart mbSendTextUser =
    _lib.lookupFunction<_MbSendTextUserC, _MbSendTextUserDart>('mb_send_text_user');

final _MbSetBoolDart mbSetSelfMute =
    _lib.lookupFunction<_MbSetBoolC, _MbSetBoolDart>('mb_set_self_mute');

final _MbSetBoolDart mbSetSelfDeaf =
    _lib.lookupFunction<_MbSetBoolC, _MbSetBoolDart>('mb_set_self_deaf');

final _MbSetStringDart mbSetSelfComment =
    _lib.lookupFunction<_MbSetStringC, _MbSetStringDart>('mb_set_self_comment');

final _MbSetTxModeDart mbSetTxMode =
    _lib.lookupFunction<_MbSetTxModeC, _MbSetTxModeDart>('mb_set_tx_mode');

final _MbSetBoolDart mbSetPttPressed =
    _lib.lookupFunction<_MbSetBoolC, _MbSetBoolDart>('mb_set_ptt_pressed');

final _MbSetFloatDart mbSetVadThreshold =
    _lib.lookupFunction<_MbSetFloatC, _MbSetFloatDart>('mb_set_vad_threshold');

final _MbSetUint32Dart mbSetVoiceHoldMs =
    _lib.lookupFunction<_MbSetUint32C, _MbSetUint32Dart>('mb_set_voice_hold_ms');

final _MbReturnStringDart _mbListInputDevicesPtr =
    _lib.lookupFunction<_MbReturnStringC, _MbReturnStringDart>('mb_list_input_devices');
String? mbListInputDevices() {
  final p = _mbListInputDevicesPtr();
  if (p.address == 0) return null;
  final s = p.toDartString();
  mbFreeString(p);
  return s;
}

final _MbReturnStringDart _mbListOutputDevicesPtr =
    _lib.lookupFunction<_MbReturnStringC, _MbReturnStringDart>('mb_list_output_devices');
String? mbListOutputDevices() {
  final p = _mbListOutputDevicesPtr();
  if (p.address == 0) return null;
  final s = p.toDartString();
  mbFreeString(p);
  return s;
}

final _MbSetDeviceDart mbSetInputDevice =
    _lib.lookupFunction<_MbSetDeviceC, _MbSetDeviceDart>('mb_set_input_device');

final _MbSetDeviceDart mbSetOutputDevice =
    _lib.lookupFunction<_MbSetDeviceC, _MbSetDeviceDart>('mb_set_output_device');

final _MbSetFloatDart mbSetInputGainDb =
    _lib.lookupFunction<_MbSetFloatC, _MbSetFloatDart>('mb_set_input_gain_db');

final _MbSetFloatDart mbSetOutputGainDb =
    _lib.lookupFunction<_MbSetFloatC, _MbSetFloatDart>('mb_set_output_gain_db');

final _MbSetUserGainDart mbSetUserGainDb =
    _lib.lookupFunction<_MbSetUserGainC, _MbSetUserGainDart>('mb_set_user_gain_db');

final _MbSetBoolDart mbSetNoiseSuppression =
    _lib.lookupFunction<_MbSetBoolC, _MbSetBoolDart>('mb_set_noise_suppression');

final _MbSetBoolDart mbSetAudioDucking =
    _lib.lookupFunction<_MbSetBoolC, _MbSetBoolDart>('mb_set_audio_ducking');

final _MbSetFloatDart mbSetAttenuateOthersDb =
    _lib.lookupFunction<_MbSetFloatC, _MbSetFloatDart>('mb_set_attenuate_others_db');

final _MbSetUint32Dart mbSetOpusBitrate =
    _lib.lookupFunction<_MbSetUint32C, _MbSetUint32Dart>('mb_set_opus_bitrate');

final _MbSetUint32Dart mbSetOpusFramesPerPacket =
    _lib.lookupFunction<_MbSetUint32C, _MbSetUint32Dart>('mb_set_opus_frames_per_packet');

final _MbVoiceTargetByteDart mbVoiceTargetClear =
    _lib.lookupFunction<_MbVoiceTargetByteC, _MbVoiceTargetByteDart>('mb_voice_target_clear');

final _MbVoiceTargetAddUsersDart mbVoiceTargetAddUsers =
    _lib.lookupFunction<_MbVoiceTargetAddUsersC, _MbVoiceTargetAddUsersDart>(
        'mb_voice_target_add_users');

final _MbVoiceTargetAddChannelDart mbVoiceTargetAddChannel =
    _lib.lookupFunction<_MbVoiceTargetAddChannelC, _MbVoiceTargetAddChannelDart>(
        'mb_voice_target_add_channel');

final _MbVoiceTargetByteDart mbUseVoiceTarget =
    _lib.lookupFunction<_MbVoiceTargetByteC, _MbVoiceTargetByteDart>('mb_use_voice_target');

final _MbRecordingStartDart mbRecordingStart =
    _lib.lookupFunction<_MbRecordingStartC, _MbRecordingStartDart>('mb_recording_start');

final _MbDisconnectDart mbRecordingStop =
    _lib.lookupFunction<_MbDisconnectC, _MbDisconnectDart>('mb_recording_stop');

final _MbBoolReturnDart mbRecordingActive =
    _lib.lookupFunction<_MbBoolReturnC, _MbBoolReturnDart>('mb_recording_active');

final _MbGenCertDart mbGenerateSelfSignedCert =
    _lib.lookupFunction<_MbGenCertC, _MbGenCertDart>('mb_generate_self_signed_cert');

final _MbFreeStringDart mbFreeString =
    _lib.lookupFunction<_MbFreeStringC, _MbFreeStringDart>('mb_free_string');

// ---------------------------------------------------------------------------
// Result codes (mirror mb_result enum)
// ---------------------------------------------------------------------------

class MbResult {
  static const ok = 0;
  static const errNotInitialized = 1;
  static const errAlreadyInit = 2;
  static const errInvalidArg = 3;
  static const errNetwork = 4;
  static const errTls = 5;
  static const errAuth = 6;
  static const errAudioDevice = 7;
  static const errInternal = 99;
}

enum TxMode { continuous, vad, ptt }
