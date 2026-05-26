import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_service.dart';
import '../../bridge/hotkey_service.dart';
import '../../settings/app_settings.dart';
import '../theme/app_theme.dart';

enum _Section { audio, voice, behavior, about }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _Section _section = _Section.audio;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionNav(
              selected: _section,
              onSelect: (s) => setState(() => _section = s),
              onClose: () => Navigator.of(context).pop(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _SectionPanel(section: _section, settings: settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionNav extends StatelessWidget {
  const _SectionNav({
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final _Section selected;
  final void Function(_Section) onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppColors.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 12, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  tooltip: 'Back',
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                const Text('Settings',
                    style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2)),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 6),
          _NavItem(
              label: 'Audio',
              icon: Icons.graphic_eq_rounded,
              isSelected: selected == _Section.audio,
              onTap: () => onSelect(_Section.audio)),
          _NavItem(
              label: 'Voice',
              icon: Icons.mic_rounded,
              isSelected: selected == _Section.voice,
              onTap: () => onSelect(_Section.voice)),
          _NavItem(
              label: 'Behavior',
              icon: Icons.tune_rounded,
              isSelected: selected == _Section.behavior,
              onTap: () => onSelect(_Section.behavior)),
          _NavItem(
              label: 'About',
              icon: Icons.info_outline_rounded,
              isSelected: selected == _Section.about,
              onTap: () => onSelect(_Section.about)),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Color bg;
    if (widget.isSelected) {
      bg = AppColors.accentSoft.withValues(alpha: 0.55);
    } else if (_hover) {
      bg = AppColors.bg2;
    } else {
      bg = Colors.transparent;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              Icon(widget.icon,
                  size: 17,
                  color: widget.isSelected
                      ? AppColors.accent
                      : AppColors.textDim),
              const SizedBox(width: 12),
              Text(widget.label,
                  style: TextStyle(
                      color: widget.isSelected
                          ? AppColors.text
                          : AppColors.textDim,
                      fontSize: 13,
                      fontWeight: widget.isSelected
                          ? FontWeight.w600
                          : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionPanel extends ConsumerWidget {
  const _SectionPanel({required this.section, required this.settings});

  final _Section section;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.read(bridgeProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 28, 36, 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            switch (section) {
              _Section.audio => _AudioSection(
                  settings: settings,
                  onDuckChange: (v) {
                    notifier.update((s) => s.copyWith(duckOtherApps: v));
                    bridge.setAudioDucking(v);
                  },
                  onInputGainChange: (v) {
                    notifier.update((s) => s.copyWith(inputGainDb: v));
                    bridge.setInputGainDb(v);
                  },
                  onOutputGainChange: (v) {
                    notifier.update((s) => s.copyWith(outputGainDb: v));
                    bridge.setOutputGainDb(v);
                  },
                  onBitrateChange: (v) {
                    notifier.update((s) => s.copyWith(opusBitrateKbps: v));
                    bridge.setOpusBitrate(v * 1000);
                  },
                ),
              _Section.voice => _VoiceSection(
                  settings: settings,
                  onTxModeChange: (m) {
                    notifier.update((s) => s.copyWith(txMode: m));
                  },
                  onPttKeyChange: (k) {
                    notifier.update((s) => s.copyWith(pttKey: k));
                  },
                ),
              _Section.behavior => _BehaviorSection(
                  settings: settings,
                  onNotificationSoundsChange: (v) => notifier
                      .update((s) => s.copyWith(notificationSounds: v)),
                  onMinimizeToTrayChange: (v) =>
                      notifier.update((s) => s.copyWith(minimizeToTray: v)),
                ),
              _Section.about => const _AboutSection(),
            },
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1)),
      );
}

class _AudioSection extends StatelessWidget {
  const _AudioSection({
    required this.settings,
    required this.onDuckChange,
    required this.onInputGainChange,
    required this.onOutputGainChange,
    required this.onBitrateChange,
  });

  final AppSettings settings;
  final void Function(bool) onDuckChange;
  final void Function(double) onInputGainChange;
  final void Function(double) onOutputGainChange;
  final void Function(int) onBitrateChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Audio'),
        _ToggleCard(
          title: 'Duck other apps while talking',
          subtitle:
              'When on, Windows lowers the volume of other apps (Spotify, '
              'games, browsers) while you have the mic open — same behavior '
              'as the Mumble and Discord clients. Turn off if you find it '
              'annoying.',
          value: settings.duckOtherApps,
          onChanged: onDuckChange,
        ),
        const _Spacer(),
        _SliderCard(
          title: 'Input gain',
          valueLabel: '${settings.inputGainDb.toStringAsFixed(1)} dB',
          value: settings.inputGainDb,
          min: -12,
          max: 12,
          divisions: 48,
          onChanged: onInputGainChange,
          subtitle: 'Boost or attenuate your mic before it hits the encoder. '
              'Best left at 0 dB unless your mic is unusually quiet or loud.',
        ),
        const _Spacer(),
        _SliderCard(
          title: 'Output gain',
          valueLabel: '${settings.outputGainDb.toStringAsFixed(1)} dB',
          value: settings.outputGainDb,
          min: -12,
          max: 12,
          divisions: 48,
          onChanged: onOutputGainChange,
          subtitle: 'Applied to all incoming voices.',
        ),
        const _Spacer(),
        _SliderCard(
          title: 'Opus bitrate',
          valueLabel: '${settings.opusBitrateKbps} kbps',
          value: settings.opusBitrateKbps.toDouble(),
          min: 16,
          max: 96,
          divisions: 80,
          onChanged: (v) => onBitrateChange(v.round()),
          subtitle:
              '32 kbps is the default and sounds good. Higher uses more '
              'bandwidth; lower is for very slow connections.',
        ),
      ],
    );
  }
}

class _VoiceSection extends StatelessWidget {
  const _VoiceSection({
    required this.settings,
    required this.onTxModeChange,
    required this.onPttKeyChange,
  });
  final AppSettings settings;
  final void Function(TxMode) onTxModeChange;
  final void Function(String) onPttKeyChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Voice'),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Transmission',
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                'How your mic is sent to the server. Voice activity '
                'detection is not implemented yet.',
                style: TextStyle(
                    color: AppColors.textDim, fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 10),
              _TxModeOption(
                label: 'Continuous',
                description: 'Always transmit while not muted.',
                selected: settings.txMode == TxMode.continuous,
                onTap: () => onTxModeChange(TxMode.continuous),
              ),
              _TxModeOption(
                label: 'Push to talk',
                description: 'Transmit only while holding the PTT key.',
                selected: settings.txMode == TxMode.ptt,
                onTap: () => onTxModeChange(TxMode.ptt),
              ),
              _TxModeOption(
                label: 'Voice activity (coming soon)',
                description:
                    'Auto-detect speech from the mic. Not implemented yet.',
                selected: settings.txMode == TxMode.vad,
                onTap: null,
              ),
            ],
          ),
        ),
        if (settings.txMode == TxMode.ptt) ...[
          const _Spacer(),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('PTT key',
                          style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                    DropdownButton<String>(
                      // Fall back to the first choice if the saved value
                      // isn't in our whitelist (older settings file, manual
                      // edit, etc.) — DropdownButton asserts the value
                      // matches one of its items.
                      value: pttKeyChoices.contains(settings.pttKey)
                          ? settings.pttKey
                          : pttKeyChoices.first,
                      dropdownColor: AppColors.bg2,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      items: [
                        for (final k in pttKeyChoices)
                          DropdownMenuItem(value: k, child: Text(_pretty(k))),
                      ],
                      onChanged: (v) {
                        if (v != null) onPttKeyChange(v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Registered system-wide, so it works even when other '
                  'apps (games, browsers) have focus.',
                  style: TextStyle(
                      color: AppColors.textDim, fontSize: 12.5, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _pretty(String code) {
    if (code.startsWith('Key')) return code.substring(3);
    return code;
  }
}

class _TxModeOption extends StatelessWidget {
  const _TxModeOption({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: !enabled
                  ? AppColors.textMuted
                  : selected
                      ? AppColors.accent
                      : AppColors.textDim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: enabled ? AppColors.text : AppColors.textMuted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BehaviorSection extends StatelessWidget {
  const _BehaviorSection({
    required this.settings,
    required this.onNotificationSoundsChange,
    required this.onMinimizeToTrayChange,
  });

  final AppSettings settings;
  final void Function(bool) onNotificationSoundsChange;
  final void Function(bool) onMinimizeToTrayChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Behavior'),
        _ToggleCard(
          title: 'Notification sounds',
          subtitle:
              'Play short tones when users join or leave your channel '
              '(not yet implemented; flag will be persisted).',
          value: settings.notificationSounds,
          onChanged: onNotificationSoundsChange,
        ),
        const _Spacer(),
        _ToggleCard(
          title: 'Minimize to tray',
          subtitle:
              'Closing the window hides it to the system tray instead of '
              'quitting (not yet implemented).',
          value: settings.minimizeToTray,
          onChanged: onMinimizeToTrayChange,
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('About'),
        const Text('mutter',
            style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('A Flutter-based Mumble client. Personal project.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.5)),
        const SizedBox(height: 14),
        const Text('Not affiliated with the official Mumble project.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }
}

class _Spacer extends StatelessWidget {
  const _Spacer();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 14);
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: child,
      );
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12.5,
                        height: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.subtitle,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final void Function(double) onChanged;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600))),
              Text(valueLabel,
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
          Text(subtitle,
              style: const TextStyle(
                  color: AppColors.textDim, fontSize: 12.5, height: 1.5)),
        ],
      ),
    );
  }
}
