import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatMessage {
  ChatMessage({
    required this.actor,
    required this.text,
    required this.ts,
    this.actorName,
    this.channelIds = const [],
    this.sessionIds = const [],
    this.system = false,
  });

  final int actor;
  /// Display name snapshotted when the message was added, so it stays correct
  /// after the user disconnects (and is no longer in the user list).
  final String? actorName;
  final String text;
  final DateTime ts;
  final List<int> channelIds;
  final List<int> sessionIds;
  final bool system;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        actor: (j['actor'] as int?) ?? 0,
        text: (j['text'] as String?) ?? '',
        ts: DateTime.now(),
        channelIds: ((j['channels'] as List?) ?? const [])
            .map((e) => e as int)
            .toList(growable: false),
        sessionIds: ((j['sessions'] as List?) ?? const [])
            .map((e) => e as int)
            .toList(growable: false),
      );

  ChatMessage withActorName(String? name) => ChatMessage(
        actor: actor,
        text: text,
        ts: ts,
        actorName: name,
        channelIds: channelIds,
        sessionIds: sessionIds,
        system: system,
      );
}

class ChatNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => const [];

  void add(ChatMessage m) {
    final next = [...state, m];
    if (next.length > 500) next.removeRange(0, next.length - 500);
    state = next;
  }

  void addSystem(String text) {
    add(ChatMessage(actor: 0, text: text, ts: DateTime.now(), system: true));
  }

  void clear() => state = const [];
}

final chatProvider =
    NotifierProvider<ChatNotifier, List<ChatMessage>>(ChatNotifier.new);
