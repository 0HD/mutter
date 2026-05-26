import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_service.dart';
import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/user_state.dart';
import '../theme/app_theme.dart';

class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key});

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastLen = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final users = ref.watch(userProvider);

    // Auto-scroll on new message.
    if (messages.length != _lastLen) {
      _lastLen = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
    }

    return Container(
      color: AppColors.bg0,
      child: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text('No messages yet.',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _MessageRow(
                      message: messages[i],
                      // Prefer the snapshotted name (correct after the user
                      // leaves the server); fall back to live lookup.
                      author: messages[i].actorName ??
                          users[messages[i].actor]?.name,
                    ),
                  ),
          ),
          const Divider(height: 1),
          _ChatInput(input: _input, onSend: _send),
        ],
      ),
    );
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final session = ref.read(connectionProvider).sessionId;
    final users = ref.read(userProvider);
    final myChannel = session == null ? null : users[session]?.channelId;
    if (myChannel == null) return;
    ref.read(bridgeProvider).sendChannelMessage(myChannel, text);
    _input.clear();
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, this.author});
  final ChatMessage message;
  final String? author;

  @override
  Widget build(BuildContext context) {
    final time =
        '${message.ts.hour.toString().padLeft(2, '0')}:${message.ts.minute.toString().padLeft(2, '0')}';
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '· ${message.text}',
          style: const TextStyle(
              color: AppColors.warning,
              fontSize: 12,
              fontStyle: FontStyle.italic),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(author ?? '#${message.actor}',
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(width: 8),
              Text(time,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 2),
          Text(message.text,
              style: const TextStyle(
                  color: AppColors.text, fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.input, required this.onSend});
  final TextEditingController input;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: input,
        decoration: const InputDecoration(
          hintText: 'Message your channel…',
          isDense: true,
        ),
        style: const TextStyle(fontSize: 14, color: AppColors.text),
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => onSend(),
      ),
    );
  }
}
