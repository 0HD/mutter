import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
