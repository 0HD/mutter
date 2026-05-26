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

    final talkingNow = !muted && conn.isConnected && level > 0.02;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      color: AppColors.bg1,
      child: Row(
        children: [
          UserAvatar(
            name: conn.username ?? '?',
            size: 32,
            talking: talkingNow,
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
          _MicIndicator(
            level: !muted && conn.isConnected ? level : 0.0,
            muted: muted,
            connected: conn.isConnected,
            onTap: conn.isConnected
                ? () => bridge.setSelfMute(!muted)
                : null,
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
    );
  }
}

/// Mic button that doubles as a tiny live-level meter — a small bar inside
/// the icon's bounding box fills with green as you speak. Replaces the full-
/// width meter that was distracting at the bottom of the sidebar.
class _MicIndicator extends StatelessWidget {
  const _MicIndicator({
    required this.level,
    required this.muted,
    required this.connected,
    required this.onTap,
  });
  final double level;
  final bool muted;
  final bool connected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final eased = level <= 0
        ? 0.0
        : (level.clamp(0.0, 1.0) * 4.0).clamp(0.0, 1.0);
    return Tooltip(
      message: muted ? 'Unmute' : 'Mute',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 32,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Center(
                child: Icon(
                  muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                  size: 18,
                  color: muted ? AppColors.muted : AppColors.textDim,
                ),
              ),
              // Slim level bar pinned to the bottom of the cell — present but
              // not the visual focus of the strip.
              Positioned(
                left: 8,
                right: 8,
                bottom: 4,
                height: 2,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.bg3,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: muted || !connected ? 0.0 : eased,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        decoration: BoxDecoration(
                          color: AppColors.speaking,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
