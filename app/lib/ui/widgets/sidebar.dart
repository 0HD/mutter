import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_service.dart';
import '../../state/audio_level.dart';
import '../../state/connection_state.dart';
import '../../state/user_state.dart';
import '../theme/app_theme.dart';
import 'channel_tree.dart';
import 'user_avatar.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    return Container(
      width: 280,
      color: AppColors.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    conn.isConnected ? 'Channels' : 'Servers',
                    style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                if (conn.isConnected)
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    tooltip: 'Disconnect',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ref.read(bridgeProvider).disconnect(),
                  ),
              ],
            ),
          ),
          const Expanded(child: _SidebarContent()),
          const Divider(height: 1),
          const _SelfStrip(),
        ],
      ),
    );
  }
}

class _SidebarContent extends ConsumerWidget {
  const _SidebarContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    if (conn.isConnected) return const ChannelTree();
    return const _FavoritesPlaceholder();
  }
}

class _FavoritesPlaceholder extends StatelessWidget {
  const _FavoritesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'No saved servers yet.\nClick "Connect" to add one.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.9), fontSize: 12),
        ),
      ),
    );
  }
}

class _SelfStrip extends ConsumerWidget {
  const _SelfStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final users = ref.watch(userProvider);
    final me = conn.sessionId == null ? null : users[conn.sessionId!];
    final muted = me?.selfMute ?? false;
    final deafened = me?.selfDeaf ?? false;
    final bridge = ref.read(bridgeProvider);
    final level = ref.watch(audioLevelProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      color: AppColors.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(
                name: conn.username ?? '?',
                size: 32,
                talking: !muted && conn.isConnected && level > 0.02,
                muted: muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conn.username ?? 'not signed in',
                      style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      conn.isConnected ? 'online' : 'offline',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                  size: 18,
                  color: muted ? AppColors.muted : null,
                ),
                tooltip: muted ? 'Unmute' : 'Mute',
                onPressed: conn.isConnected
                    ? () => bridge.setSelfMute(!muted)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(
                  deafened ? Icons.headset_off_rounded : Icons.headset_rounded,
                  size: 18,
                  color: deafened ? AppColors.muted : null,
                ),
                tooltip: deafened ? 'Undeafen' : 'Deafen',
                onPressed: conn.isConnected
                    ? () => bridge.setSelfDeaf(!deafened)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MicLevelBar(
              level: conn.isConnected && !muted ? level : 0.0,
              active: conn.isConnected && !muted),
        ],
      ),
    );
  }
}

class _MicLevelBar extends StatelessWidget {
  const _MicLevelBar({required this.level, required this.active});
  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Convert RMS to a perceptual scale. RMS is roughly [0..1] but real
    // speech sits around 0.05..0.3, so a sqrt curve helps the bar feel
    // responsive without going slammed.
    final eased = level <= 0
        ? 0.0
        : (level.clamp(0.0, 1.0) * 4.0).clamp(0.0, 1.0);
    return SizedBox(
      height: 5,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.bg3,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          FractionallySizedBox(
            widthFactor: eased,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              decoration: BoxDecoration(
                color: active ? AppColors.speaking : AppColors.textMuted,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
