import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Convert a volume percentage (0% silent, 100% unity, 200% +6 dB) to a
/// gain in decibels. Treats 0% as effectively muted (-60 dB).
double dbFromPercent(num percent) {
  if (percent <= 0) return -60.0;
  return 20.0 * (math.log(percent / 100.0) / math.ln10);
}

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
    this.inputGainPercent = 100,
    this.outputGainPercent = 100,
    this.opusBitrateKbps = 32,
    this.notificationSounds = true,
    this.minimizeToTray = false,
    this.txMode = TxMode.continuous,
    this.pttKey = 'KeyV',
    this.userVolumes = const {},
    this.favorites = const [],
  });

  // Audio (volume as percent — 100 = unity, 200 = +6 dB, 0 = silent).
  final bool duckOtherApps;
  final int inputGainPercent;
  final int outputGainPercent;
  final int opusBitrateKbps;

  // Voice
  final TxMode txMode;
  final String pttKey;

  // Behavior
  final bool notificationSounds;
  final bool minimizeToTray;

  // Per-user output volume (session ID -> percent). Sessions are not stable
  // across reconnects so this is effectively per-server-per-session.
  final Map<int, int> userVolumes;

  // Saved servers.
  final List<ServerFavorite> favorites;

  AppSettings copyWith({
    bool? duckOtherApps,
    int? inputGainPercent,
    int? outputGainPercent,
    int? opusBitrateKbps,
    bool? notificationSounds,
    bool? minimizeToTray,
    TxMode? txMode,
    String? pttKey,
    Map<int, int>? userVolumes,
    List<ServerFavorite>? favorites,
  }) =>
      AppSettings(
        duckOtherApps: duckOtherApps ?? this.duckOtherApps,
        inputGainPercent: inputGainPercent ?? this.inputGainPercent,
        outputGainPercent: outputGainPercent ?? this.outputGainPercent,
        opusBitrateKbps: opusBitrateKbps ?? this.opusBitrateKbps,
        notificationSounds: notificationSounds ?? this.notificationSounds,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
        txMode: txMode ?? this.txMode,
        pttKey: pttKey ?? this.pttKey,
        userVolumes: userVolumes ?? this.userVolumes,
        favorites: favorites ?? this.favorites,
      );

  Map<String, dynamic> toJson() => {
        'duckOtherApps': duckOtherApps,
        'inputGainPercent': inputGainPercent,
        'outputGainPercent': outputGainPercent,
        'opusBitrateKbps': opusBitrateKbps,
        'notificationSounds': notificationSounds,
        'minimizeToTray': minimizeToTray,
        'txMode': txMode.name,
        'pttKey': pttKey,
        'userVolumes':
            userVolumes.map((k, v) => MapEntry(k.toString(), v)),
        'favorites': favorites.map((f) => f.toJson()).toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        duckOtherApps: (j['duckOtherApps'] as bool?) ?? true,
        inputGainPercent: (j['inputGainPercent'] as int?) ?? 100,
        outputGainPercent: (j['outputGainPercent'] as int?) ?? 100,
        opusBitrateKbps: (j['opusBitrateKbps'] as int?) ?? 32,
        notificationSounds: (j['notificationSounds'] as bool?) ?? true,
        minimizeToTray: (j['minimizeToTray'] as bool?) ?? false,
        txMode: TxMode.values.firstWhere(
          (m) => m.name == (j['txMode'] as String?),
          orElse: () => TxMode.continuous,
        ),
        pttKey: (j['pttKey'] as String?) ?? 'KeyV',
        userVolumes: ((j['userVolumes'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(int.parse(k), (v as num).toInt())),
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
