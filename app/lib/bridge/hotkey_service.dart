import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import 'bindings.dart' as nb;

/// Routes the push-to-talk binding to a system-wide low-level keyboard hook
/// installed by the native bridge. We can't use Windows' RegisterHotKey for
/// PTT because it only delivers presses, not releases — the bridge's
/// WH_KEYBOARD_LL hook sees both edges of the key.
class HotkeyService {
  HotkeyService(this._ref);
  final Ref _ref;
  int _installedVk = 0;

  void initialize() {
    _applyFromSettings();
    _ref.listen<AppSettings>(settingsProvider, (prev, next) {
      if (prev?.pttKey != next.pttKey || prev?.txMode != next.txMode) {
        _applyFromSettings();
      }
    });
  }

  void _applyFromSettings() {
    final settings = _ref.read(settingsProvider);
    final vk = settings.txMode == TxMode.ptt
        ? _vkFromName(settings.pttKey) ?? 0
        : 0;
    if (vk == _installedVk) return;
    nb.mbInstallPttHook(vk);
    _installedVk = vk;
  }

  /// Maps the dropdown's PTT-key name to a Windows virtual-key code.
  static int? _vkFromName(String name) => _vkMap[name];
}

const Map<String, int> _vkMap = {
  // Letters
  'KeyV': 0x56,
  'KeyB': 0x42,
  'KeyT': 0x54,
  'KeyZ': 0x5A,
  'KeyX': 0x58,
  'KeyC': 0x43,
  'Space': 0x20,
  'F1': 0x70,
  'F2': 0x71,
  'F3': 0x72,
  'F4': 0x73,
  'F5': 0x74,
  'F6': 0x75,
  'F7': 0x76,
  'F8': 0x77,
};

/// Convenience list shown by the settings UI.
const pttKeyChoices = [
  'KeyV',
  'KeyB',
  'KeyT',
  'KeyZ',
  'KeyX',
  'KeyC',
  'Space',
  'F1',
  'F2',
  'F3',
  'F4',
  'F5',
  'F6',
  'F7',
  'F8',
];

final hotkeyServiceProvider = Provider<HotkeyService>((ref) {
  final svc = HotkeyService(ref);
  svc.initialize();
  return svc;
});
