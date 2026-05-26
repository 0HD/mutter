import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_service.dart';
import '../../state/channel_state.dart';
import '../../state/connection_state.dart';
import '../../state/user_state.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

class ChannelTree extends ConsumerWidget {
  const ChannelTree({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelProvider);
    final users = ref.watch(userProvider);
    final conn = ref.watch(connectionProvider);

    if (channels.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Waiting for channels…',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    // Build tree: group children by parent.
    final children = <int?, List<ChannelInfo>>{};
    for (final c in channels.values) {
      children.putIfAbsent(c.parent, () => []).add(c);
    }
    for (final list in children.values) {
      list.sort((a, b) {
        final p = a.position.compareTo(b.position);
        return p != 0 ? p : a.name.compareTo(b.name);
      });
    }

    final usersByChannel = <int, List<UserInfo>>{};
    for (final u in users.values) {
      usersByChannel.putIfAbsent(u.channelId, () => []).add(u);
    }
    for (final list in usersByChannel.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    // The root channel in Mumble has id 0 and no parent.
    final root = channels[0];

    final myChannel = users[conn.sessionId]?.channelId;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (root != null)
          _ChannelNode(
            channel: root,
            depth: 0,
            childrenByParent: children,
            usersByChannel: usersByChannel,
            myChannelId: myChannel,
          ),
      ],
    );
  }
}

class _ChannelNode extends ConsumerWidget {
  const _ChannelNode({
    required this.channel,
    required this.depth,
    required this.childrenByParent,
    required this.usersByChannel,
    required this.myChannelId,
  });

  final ChannelInfo channel;
  final int depth;
  final Map<int?, List<ChannelInfo>> childrenByParent;
  final Map<int, List<UserInfo>> usersByChannel;
  final int? myChannelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subChannels = childrenByParent[channel.id] ?? const [];
    final inHere = usersByChannel[channel.id] ?? const [];
    final isMine = myChannelId == channel.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChannelRow(
          channel: channel,
          depth: depth,
          isMine: isMine,
          userCount: inHere.length,
          onTap: () =>
              ref.read(bridgeProvider).joinChannel(channel.id),
        ),
        for (final u in inHere)
          _UserRow(user: u, depth: depth + 1, isSelf: u.session == ref.watch(connectionProvider).sessionId),
        for (final c in subChannels)
          _ChannelNode(
            channel: c,
            depth: depth + 1,
            childrenByParent: childrenByParent,
            usersByChannel: usersByChannel,
            myChannelId: myChannelId,
          ),
      ],
    );
  }
}

class _ChannelRow extends StatefulWidget {
  const _ChannelRow({
    required this.channel,
    required this.depth,
    required this.isMine,
    required this.userCount,
    required this.onTap,
  });
  final ChannelInfo channel;
  final int depth;
  final bool isMine;
  final int userCount;
  final VoidCallback onTap;

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onDoubleTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.only(
              left: 12.0 + widget.depth * 14, right: 12, top: 6, bottom: 6),
          color: widget.isMine
              ? AppColors.accentSoft.withValues(alpha: 0.55)
              : _hover
                  ? AppColors.bg2
                  : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.channel.temporary
                    ? Icons.timer_outlined
                    : Icons.tag_rounded,
                size: 14,
                color: widget.isMine ? AppColors.accent : AppColors.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.channel.name.isEmpty ? 'Root' : widget.channel.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isMine ? AppColors.text : AppColors.text,
                    fontWeight:
                        widget.isMine ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (widget.userCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('${widget.userCount}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.depth,
    required this.isSelf,
  });
  final UserInfo user;
  final int depth;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final icons = <Widget>[];
    if (user.selfDeaf || user.deaf) {
      icons.add(const Icon(Icons.headset_off_rounded,
          size: 13, color: AppColors.muted));
    }
    if (user.prioritySpeaker) {
      icons.add(const Icon(Icons.star_rounded,
          size: 13, color: AppColors.warning));
    }
    if (user.recording) {
      icons.add(const Icon(Icons.fiber_manual_record,
          size: 13, color: AppColors.muted));
    }

    return Padding(
      padding: EdgeInsets.only(
          left: 14.0 + depth * 14, right: 12, top: 5, bottom: 5),
      child: Row(
        children: [
          UserAvatar(
            name: user.name,
            size: 22,
            talking: user.talking,
            muted: user.selfMute || user.mute,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              user.name.isEmpty ? '#${user.session}' : user.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: isSelf ? AppColors.text : AppColors.textDim,
                fontWeight: isSelf ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          for (final w in icons)
            Padding(padding: const EdgeInsets.only(left: 4), child: w),
        ],
      ),
    );
  }
}
