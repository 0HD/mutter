import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/connection_quality.dart';
import '../../state/connection_state.dart';
import '../screens/settings_screen.dart';
import '../theme/app_theme.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final subtitle = switch (conn.phase) {
      ConnectionPhase.disconnected => 'not connected',
      ConnectionPhase.connecting => 'connecting…',
      ConnectionPhase.authenticating => 'authenticating…',
      ConnectionPhase.synchronizing => 'synchronizing…',
      ConnectionPhase.connected =>
        '${conn.username ?? '?'} @ ${conn.host ?? '?'}',
      ConnectionPhase.error => conn.errorMessage ?? 'error',
    };

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.bg1,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: conn.isConnected
                  ? AppColors.speaking
                  : conn.isBusy
                      ? AppColors.warning
                      : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          const Text('mutter',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                  letterSpacing: 0.3)),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 14,
            color: AppColors.border,
          ),
          const SizedBox(width: 12),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDim,
                  letterSpacing: 0.2)),
          const Spacer(),
          if (conn.isConnected) const _PingBadge(),
          if (conn.isConnected) const SizedBox(width: 6),
          _IconBtn(
              icon: Icons.settings_rounded,
              tooltip: 'Settings',
              onTap: () => Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SettingsScreen(),
                      transitionsBuilder: (_, anim, __, child) {
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.02),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                                parent: anim, curve: Curves.easeOut)),
                            child: child,
                          ),
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 200),
                    ),
                  )),
        ],
      ),
    );
  }
}

class _PingBadge extends ConsumerWidget {
  const _PingBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(connectionQualityProvider);
    if (!q.hasData) {
      return const SizedBox(
        width: 56,
        child: Text('…',
            textAlign: TextAlign.right,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      );
    }
    final ping = q.tcpPingMs.round();
    final loss = (q.lossRatio * 100).round();
    final color = ping < 60
        ? AppColors.speaking
        : ping < 150
            ? AppColors.warning
            : AppColors.muted;
    return Tooltip(
      message: 'TCP ping ${q.tcpPingMs.toStringAsFixed(1)} ms\n'
          'packets — good ${q.good}, late ${q.late}, lost ${q.lost}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('${ping}ms',
                style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 11.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600)),
            if (loss > 0) ...[
              const SizedBox(width: 6),
              Text('· $loss% loss',
                  style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18, color: AppColors.textDim),
        ),
      ),
    );
  }
}
