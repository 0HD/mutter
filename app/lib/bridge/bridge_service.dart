import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import '../state/audio_level.dart';
import '../state/channel_state.dart';
import '../state/chat_state.dart';
import '../state/connection_quality.dart';
import '../state/connection_state.dart';
import '../state/user_state.dart';
import 'bindings.dart' as nb;

/// High-level service that owns the FFI bridge and routes events from the
/// native side into Riverpod state.
class BridgeService {
  BridgeService(this._ref);

  final Ref _ref;
  ReceivePort? _eventPort;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    nb.mbInit();
    nb.mbInitDartApi(NativeApi.initializeApiDLData);

    _eventPort = ReceivePort('mutter.bridge.events');
    _eventPort!.listen(_onEvent);
    nb.mbSetEventPort(_eventPort!.sendPort.nativePort);

    // Push the current settings into the bridge and react to future edits.
    _applySettings(_ref.read(settingsProvider));
    _ref.listen<AppSettings>(settingsProvider, (prev, next) {
      _applySettings(next);
    });
  }

  void _applySettings(AppSettings s) {
    nb.mbSetAudioDucking(s.duckOtherApps);
    nb.mbSetInputGainDb(s.inputGainDb);
    nb.mbSetOutputGainDb(s.outputGainDb);
    nb.mbSetOpusBitrate(s.opusBitrateKbps * 1000);
    nb.mbSetTxMode(s.txMode.index);
    // Per-user volumes — push every one (the bridge ignores 0 dB entries).
    for (final entry in s.userVolumesDb.entries) {
      nb.mbSetUserGainDb(entry.key, entry.value);
    }
  }

  void dispose() {
    nb.mbDisconnect();
    nb.mbSetEventPort(0);
    _eventPort?.close();
    nb.mbShutdown();
    _initialized = false;
  }

  /// Connect to a Mumble server. Returns immediately; progress arrives as
  /// events on the connectionProvider state.
  void connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? certPem,
    String? keyPem,
  }) {
    final notifier = _ref.read(connectionProvider.notifier);
    notifier.setIdentity(host, username);
    notifier.setPhase(ConnectionPhase.connecting);

    final hostPtr = host.toNativeUtf8();
    final userPtr = username.toNativeUtf8();
    final pwPtr = (password ?? '').isEmpty ? nullptr : password!.toNativeUtf8();
    final certPtr = (certPem ?? '').isEmpty ? nullptr : certPem!.toNativeUtf8();
    final keyPtr = (keyPem ?? '').isEmpty ? nullptr : keyPem!.toNativeUtf8();

    final params = calloc<nb.MbConnectParams>();
    params.ref
      ..host = hostPtr
      ..port = port
      ..username = userPtr
      ..password = pwPtr.cast()
      ..certPem = certPtr.cast()
      ..keyPem = keyPtr.cast()
      ..tokens = nullptr;

    try {
      nb.mbConnect(params);
    } finally {
      calloc.free(params);
      malloc.free(hostPtr);
      malloc.free(userPtr);
      if (pwPtr != nullptr) malloc.free(pwPtr);
      if (certPtr != nullptr) malloc.free(certPtr);
      if (keyPtr != nullptr) malloc.free(keyPtr);
    }
  }

  void disconnect() => nb.mbDisconnect();

  void joinChannel(int channelId) => nb.mbJoinChannel(channelId);

  void setSelfMute(bool mute) => nb.mbSetSelfMute(mute);
  void setSelfDeaf(bool deaf) => nb.mbSetSelfDeaf(deaf);

  void setAudioDucking(bool duck) => nb.mbSetAudioDucking(duck);
  void setInputGainDb(double db) => nb.mbSetInputGainDb(db);
  void setOutputGainDb(double db) => nb.mbSetOutputGainDb(db);
  void setOpusBitrate(int bps) => nb.mbSetOpusBitrate(bps);

  void setTxMode(TxMode mode) => nb.mbSetTxMode(mode.index);
  void setPttPressed(bool pressed) => nb.mbSetPttPressed(pressed);
  void setUserGainDb(int sessionId, double db) =>
      nb.mbSetUserGainDb(sessionId, db);

  void sendChannelMessage(int channelId, String text, {bool tree = false}) {
    final p = text.toNativeUtf8();
    try {
      nb.mbSendTextChannel(channelId, tree, p);
    } finally {
      malloc.free(p);
    }
    // Mumble doesn't echo our own text messages back, so add it locally.
    final me = _ref.read(connectionProvider).sessionId;
    if (me != null) {
      _ref.read(chatProvider.notifier).add(ChatMessage(
            actor: me,
            text: text,
            ts: DateTime.now(),
            channelIds: [channelId],
          ));
    }
  }

  void sendUserMessage(int sessionId, String text) {
    final p = text.toNativeUtf8();
    try {
      nb.mbSendTextUser(sessionId, p);
    } finally {
      malloc.free(p);
    }
    final me = _ref.read(connectionProvider).sessionId;
    if (me != null) {
      _ref.read(chatProvider.notifier).add(ChatMessage(
            actor: me,
            text: text,
            ts: DateTime.now(),
            sessionIds: [sessionId],
          ));
    }
  }

  void _onEvent(dynamic msg) {
    if (msg is! String) return;
    Map<String, dynamic> j;
    try {
      j = json.decode(msg) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (j['type']) {
      case 'connection_state':
        _onConnectionState(j);
        break;
      case 'server_sync':
        _onServerSync(j);
        break;
      case 'channel_state':
        _ref.read(channelProvider.notifier).upsert(ChannelInfo.fromJson(j));
        break;
      case 'channel_remove':
        _ref.read(channelProvider.notifier).remove(j['id'] as int);
        break;
      case 'user_state':
        _ref.read(userProvider.notifier).upsert(UserInfo.fromJson(j));
        break;
      case 'user_remove':
        _ref.read(userProvider.notifier).remove(j['session'] as int);
        break;
      case 'text_message':
        _ref.read(chatProvider.notifier).add(ChatMessage.fromJson(j));
        break;
      case 'permission_denied':
        _ref.read(chatProvider.notifier).addSystem(
            'Permission denied: ${j['reason'] ?? '(no reason)'}');
        break;
      case 'server_config':
        // could surface server welcome banner; ignored for now
        break;
      case 'diag':
        _ref.read(chatProvider.notifier).addSystem(
            '[${j['source']}] ${j['message']}');
        break;
      case 'user_talking':
        _ref
            .read(userProvider.notifier)
            .setTalking(j['session'] as int, j['talking'] as bool);
        break;
      case 'audio_level':
        _ref
            .read(audioLevelProvider.notifier)
            .set((j['rms'] as num).toDouble());
        break;
      case 'ping_stats':
        _ref.read(connectionQualityProvider.notifier).update(j);
        break;
    }
  }

  void _onConnectionState(Map<String, dynamic> j) {
    final notifier = _ref.read(connectionProvider.notifier);
    final state = j['state'] as String;
    final reason = j['reason'] as String?;
    switch (state) {
      case 'connecting':
        notifier.setPhase(ConnectionPhase.connecting);
        break;
      case 'authenticating':
        notifier.setPhase(ConnectionPhase.authenticating);
        break;
      case 'connected':
        notifier.setPhase(ConnectionPhase.connected);
        break;
      case 'disconnected':
        notifier.disconnected();
        _ref.read(channelProvider.notifier).clear();
        _ref.read(userProvider.notifier).clear();
        _ref.read(chatProvider.notifier).clear();
        _ref.read(connectionQualityProvider.notifier).reset();
        break;
      case 'error':
        notifier.setPhase(ConnectionPhase.error, error: reason);
        break;
    }
  }

  void _onServerSync(Map<String, dynamic> j) {
    final notifier = _ref.read(connectionProvider.notifier);
    notifier.setPhase(ConnectionPhase.connected,
        welcome: j['welcome'] as String?);
    notifier.setSession(j['session'] as int);
  }
}

final bridgeProvider = Provider<BridgeService>((ref) {
  final svc = BridgeService(ref);
  svc.initialize();
  ref.onDispose(svc.dispose);
  return svc;
});
