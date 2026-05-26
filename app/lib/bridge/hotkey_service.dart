import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../settings/app_settings.dart';
import 'bridge_service.dart';

/// Registers a system-wide hotkey for push-to-talk. Pressed = transmitting;
/// released = silent. The PTT key is read from settings and re-registered
/// whenever it changes.
class HotkeyService {
  HotkeyService(this._ref);
  final Ref _ref;
  HotKey? _pttHotkey;

  Future<void> initialize() async {
    await hotKeyManager.unregisterAll();
    await _applyFromSettings();
    _ref.listen<AppSettings>(settingsProvider, (prev, next) async {
      if (prev?.pttKey != next.pttKey || prev?.txMode != next.txMode) {
        await _applyFromSettings();
      }
    });
  }

  Future<void> _applyFromSettings() async {
    final settings = _ref.read(settingsProvider);
    // Unregister any existing PTT binding.
    if (_pttHotkey != null) {
      try {
        await hotKeyManager.unregister(_pttHotkey!);
      } catch (_) {/* ignore */}
      _pttHotkey = null;
    }
    // Only register the hotkey when the user is actually using PTT.
    if (settings.txMode != TxMode.ptt) return;
    final code = _physicalKeyFromName(settings.pttKey);
    if (code == null) return;
    final hk = HotKey(
      key: code,
      scope: HotKeyScope.system,
    );
    try {
      await hotKeyManager.register(
        hk,
        keyDownHandler: (_) => _ref.read(bridgeProvider).setPttPressed(true),
        keyUpHandler: (_) => _ref.read(bridgeProvider).setPttPressed(false),
      );
      _pttHotkey = hk;
    } catch (_) {
      // Common failure: the key combination is already registered by another
      // process, or the user picked a key that needs a modifier. Silent
      // fallback — settings UI will let them pick another.
    }
  }

  PhysicalKeyboardKey? _physicalKeyFromName(String name) {
    // Common single-key PTT bindings. hotkey_manager expects PhysicalKeyboardKey
    // (from flutter/services). We expose a small whitelist that's safe to use
    // as a system hotkey without modifiers.
    const map = <String, PhysicalKeyboardKey>{
      'KeyV': PhysicalKeyboardKey.keyV,
      'KeyB': PhysicalKeyboardKey.keyB,
      'KeyT': PhysicalKeyboardKey.keyT,
      'KeyZ': PhysicalKeyboardKey.keyZ,
      'KeyX': PhysicalKeyboardKey.keyX,
      'KeyC': PhysicalKeyboardKey.keyC,
      'Space': PhysicalKeyboardKey.space,
      'F1': PhysicalKeyboardKey.f1,
      'F2': PhysicalKeyboardKey.f2,
      'F3': PhysicalKeyboardKey.f3,
      'F4': PhysicalKeyboardKey.f4,
      'F5': PhysicalKeyboardKey.f5,
      'F6': PhysicalKeyboardKey.f6,
      'F7': PhysicalKeyboardKey.f7,
      'F8': PhysicalKeyboardKey.f8,
    };
    return map[name];
  }
}

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
