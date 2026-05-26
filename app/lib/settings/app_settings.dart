import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  const AppSettings({
    this.duckOtherApps = true,
    this.inputGainDb = 0.0,
    this.outputGainDb = 0.0,
    this.opusBitrateKbps = 32,
    this.notificationSounds = true,
    this.minimizeToTray = false,
    this.attenuateOthersDb = 0.0,
  });

  // Audio
  final bool duckOtherApps;
  final double inputGainDb;
  final double outputGainDb;
  final int opusBitrateKbps;
  final double attenuateOthersDb;

  // Behavior
  final bool notificationSounds;
  final bool minimizeToTray;

  AppSettings copyWith({
    bool? duckOtherApps,
    double? inputGainDb,
    double? outputGainDb,
    int? opusBitrateKbps,
    double? attenuateOthersDb,
    bool? notificationSounds,
    bool? minimizeToTray,
  }) =>
      AppSettings(
        duckOtherApps: duckOtherApps ?? this.duckOtherApps,
        inputGainDb: inputGainDb ?? this.inputGainDb,
        outputGainDb: outputGainDb ?? this.outputGainDb,
        opusBitrateKbps: opusBitrateKbps ?? this.opusBitrateKbps,
        attenuateOthersDb: attenuateOthersDb ?? this.attenuateOthersDb,
        notificationSounds: notificationSounds ?? this.notificationSounds,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      );

  Map<String, dynamic> toJson() => {
        'duckOtherApps': duckOtherApps,
        'inputGainDb': inputGainDb,
        'outputGainDb': outputGainDb,
        'opusBitrateKbps': opusBitrateKbps,
        'attenuateOthersDb': attenuateOthersDb,
        'notificationSounds': notificationSounds,
        'minimizeToTray': minimizeToTray,
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
