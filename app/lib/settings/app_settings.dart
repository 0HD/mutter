import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum TxMode { continuous, vad, ptt }

class ServerFavorite {
  const ServerFavorite({
    required this.name,
    required this.host,
    this.port = 64738,
    this.username = '',
  });
  final String name;
  final String host;
  final int port;
  final String username;

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
      };

  factory ServerFavorite.fromJson(Map<String, dynamic> j) => ServerFavorite(
        name: (j['name'] as String?) ?? '',
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as int?) ?? 64738,
        username: (j['username'] as String?) ?? '',
      );
}

class AppSettings {
  const AppSettings({
    this.duckOtherApps = true,
    this.inputGainDb = 0.0,
    this.outputGainDb = 0.0,
    this.opusBitrateKbps = 32,
    this.notificationSounds = true,
    this.minimizeToTray = false,
    this.attenuateOthersDb = 0.0,
    this.txMode = TxMode.continuous,
    this.pttKey = 'KeyV',
    this.userVolumesDb = const {},
    this.favorites = const [],
  });

  // Audio
  final bool duckOtherApps;
  final double inputGainDb;
  final double outputGainDb;
  final int opusBitrateKbps;
  final double attenuateOthersDb;

  // Voice
  final TxMode txMode;
  final String pttKey; // hotkey_manager KeyCode name, e.g. "KeyV", "Space"

  // Behavior
  final bool notificationSounds;
  final bool minimizeToTray;

  // Per-user volume (session ID -> dB). Note: sessions are not stable across
  // reconnects so this is effectively per-server-per-session.
  final Map<int, double> userVolumesDb;

  // Saved servers.
  final List<ServerFavorite> favorites;

  AppSettings copyWith({
    bool? duckOtherApps,
    double? inputGainDb,
    double? outputGainDb,
    int? opusBitrateKbps,
    double? attenuateOthersDb,
    bool? notificationSounds,
    bool? minimizeToTray,
    TxMode? txMode,
    String? pttKey,
    Map<int, double>? userVolumesDb,
    List<ServerFavorite>? favorites,
  }) =>
      AppSettings(
        duckOtherApps: duckOtherApps ?? this.duckOtherApps,
        inputGainDb: inputGainDb ?? this.inputGainDb,
        outputGainDb: outputGainDb ?? this.outputGainDb,
        opusBitrateKbps: opusBitrateKbps ?? this.opusBitrateKbps,
        attenuateOthersDb: attenuateOthersDb ?? this.attenuateOthersDb,
        notificationSounds: notificationSounds ?? this.notificationSounds,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
        txMode: txMode ?? this.txMode,
        pttKey: pttKey ?? this.pttKey,
        userVolumesDb: userVolumesDb ?? this.userVolumesDb,
        favorites: favorites ?? this.favorites,
      );

  Map<String, dynamic> toJson() => {
        'duckOtherApps': duckOtherApps,
        'inputGainDb': inputGainDb,
        'outputGainDb': outputGainDb,
        'opusBitrateKbps': opusBitrateKbps,
        'attenuateOthersDb': attenuateOthersDb,
        'notificationSounds': notificationSounds,
        'minimizeToTray': minimizeToTray,
        'txMode': txMode.name,
        'pttKey': pttKey,
        'userVolumesDb':
            userVolumesDb.map((k, v) => MapEntry(k.toString(), v)),
        'favorites': favorites.map((f) => f.toJson()).toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        duckOtherApps: (j['duckOtherApps'] as bool?) ?? true,
        inputGainDb: (j['inputGainDb'] as num?)?.toDouble() ?? 0.0,
        outputGainDb: (j['outputGainDb'] as num?)?.toDouble() ?? 0.0,
        opusBitrateKbps: (j['opusBitrateKbps'] as int?) ?? 32,
        attenuateOthersDb:
            (j['attenuateOthersDb'] as num?)?.toDouble() ?? 0.0,
        notificationSounds: (j['notificationSounds'] as bool?) ?? true,
        minimizeToTray: (j['minimizeToTray'] as bool?) ?? false,
        txMode: TxMode.values.firstWhere(
          (m) => m.name == (j['txMode'] as String?),
          orElse: () => TxMode.continuous,
        ),
        pttKey: (j['pttKey'] as String?) ?? 'KeyV',
        userVolumesDb: ((j['userVolumesDb'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(int.parse(k), (v as num).toDouble())),
        favorites: ((j['favorites'] as List<dynamic>?) ?? const [])
            .map((e) => ServerFavorite.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  File? _file;
  Timer? _saveDebounce;

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}settings.json');
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        state = AppSettings.fromJson(json.decode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Fall back to defaults on any disk error.
    }
  }

  Future<void> _save() async {
    if (_file == null) return;
    try {
      await _file!.writeAsString(json.encode(state.toJson()));
    } catch (_) {
      // Disk errors are silent — we'll retry on next change.
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _save);
  }

  void update(AppSettings Function(AppSettings) f) {
    state = f(state);
    _scheduleSave();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
