import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_service.dart';
import '../../settings/app_settings.dart';
import '../../state/channel_expansion.dart';
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
    final collapsed = ref.watch(channelExpansionProvider).contains(channel.id);
    final hasChildren = subChannels.isNotEmpty || inHere.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChannelRow(
          channel: channel,
          depth: depth,
          isMine: isMine,
          userCount: inHere.length,
          collapsed: collapsed,
          hasChildren: hasChildren,
          onTap: () =>
              ref.read(bridgeProvider).joinChannel(channel.id),
          onToggleCollapse: () =>
              ref.read(channelExpansionProvider.notifier).toggle(channel.id),
        ),
        if (!collapsed) ...[
          for (final u in inHere)
            _UserRow(
                user: u,
                depth: depth + 1,
                isSelf: u.session == ref.watch(connectionProvider).sessionId),
          for (final c in subChannels)
            _ChannelNode(
              channel: c,
              depth: depth + 1,
              childrenByParent: childrenByParent,
              usersByChannel: usersByChannel,
              myChannelId: myChannelId,
            ),
        ],
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
    required this.collapsed,
    required this.hasChildren,
    required this.onTap,
    required this.onToggleCollapse,
  });
  final ChannelInfo channel;
  final int depth;
  final bool isMine;
  final int userCount;
  final bool collapsed;
  final bool hasChildren;
  final VoidCallback onTap;
  final VoidCallback onToggleCollapse;

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
              left: 4.0 + widget.depth * 14, right: 12, top: 6, bottom: 6),
          color: widget.isMine
              ? AppColors.accentSoft.withValues(alpha: 0.55)
              : _hover
                  ? AppColors.bg2
                  : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: widget.hasChildren
                    ? GestureDetector(
                        onTap: widget.onToggleCollapse,
                        child: AnimatedRotation(
                          turns: widget.collapsed ? -0.25 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: const Icon(Icons.expand_more_rounded,
                              size: 16, color: AppColors.textMuted),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 2),
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

class _UserRow extends ConsumerWidget {
  const _UserRow({
    required this.user,
    required this.depth,
    required this.isSelf,
  });
  final UserInfo user;
  final int depth;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = <Widget>[];
    if (user.selfMute || user.mute) {
      icons.add(Icon(Icons.mic_off_rounded,
          size: 14, color: AppColors.muted.withValues(alpha: 0.85)));
    }
    if (user.selfDeaf || user.deaf) {
      icons.add(Icon(Icons.headset_off_rounded,
          size: 14, color: AppColors.muted.withValues(alpha: 0.85)));
    }
    if (user.prioritySpeaker) {
      icons.add(const Icon(Icons.star_rounded,
          size: 14, color: AppColors.warning));
    }
    if (user.recording) {
      icons.add(const Icon(Icons.fiber_manual_record,
          size: 14, color: AppColors.muted));
    }

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(
          context, ref, details.globalPosition),
      child: Padding(
        padding: EdgeInsets.only(
            left: 10.0 + depth * 14, right: 12, top: 3, bottom: 3),
        child: Row(
          children: [
            UserAvatar(name: user.name, size: 22, talking: user.talking),
            const SizedBox(width: 8),
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
              Padding(padding: const EdgeInsets.only(left: 5), child: w),
          ],
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, Offset pos) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final rect = RelativeRect.fromLTRB(pos.dx, pos.dy,
        overlay.size.width - pos.dx, overlay.size.height - pos.dy);

    final settings = ref.read(settingsProvider);
    final currentPercent = settings.userVolumes[user.session] ?? 100;

    await showMenu<void>(
      context: context,
      position: rect,
      color: AppColors.bg2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      items: [
        // No volume control on yourself; your own voice doesn't play back.
        if (!isSelf)
          PopupMenuItem<void>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _UserVolumeMenu(
              user: user,
              initialPercent: currentPercent,
              onChange: (percent) {
                final settings = ref.read(settingsProvider);
                final newMap = Map<int, int>.from(settings.userVolumes);
                if (percent == 100) {
                  newMap.remove(user.session);
                } else {
                  newMap[user.session] = percent;
                }
                ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(userVolumes: newMap));
                ref
                    .read(bridgeProvider)
                    .setUserVolumePercent(user.session, percent);
              },
            ),
          ),
        if (user.comment.isNotEmpty)
          PopupMenuItem<void>(
            enabled: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                user.comment,
                style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ),
        PopupMenuItem<void>(
          onTap: () => Clipboard.setData(ClipboardData(text: user.name)),
          child: const Row(
            children: [
              Icon(Icons.content_copy_rounded,
                  size: 14, color: AppColors.textDim),
              SizedBox(width: 8),
              Text('Copy name',
                  style: TextStyle(color: AppColors.text, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserVolumeMenu extends StatefulWidget {
  const _UserVolumeMenu({
    required this.user,
    required this.initialPercent,
    required this.onChange,
  });
  final UserInfo user;
  final int initialPercent;
  final void Function(int) onChange;

  @override
  State<_UserVolumeMenu> createState() => _UserVolumeMenuState();
}

class _UserVolumeMenuState extends State<_UserVolumeMenu> {
  late int _percent = widget.initialPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                  name: widget.user.name,
                  size: 24,
                  talking: widget.user.talking),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.user.name.isEmpty
                      ? '#${widget.user.session}'
                      : widget.user.name,
                  style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Text('$_percent%',
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Slider(
            value: _percent.clamp(0, 200).toDouble(),
            min: 0,
            max: 200,
            divisions: 40,
            onChanged: (v) {
              setState(() => _percent = v.round());
              widget.onChange(_percent);
            },
          ),
        ],
      ),
    );
  }
}
