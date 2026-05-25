import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserInfo {
  UserInfo({
    required this.session,
    required this.name,
    required this.channelId,
    this.mute = false,
    this.deaf = false,
    this.selfMute = false,
    this.selfDeaf = false,
    this.suppress = false,
    this.prioritySpeaker = false,
    this.recording = false,
    this.comment = '',
  });

  final int session;
  final String name;
  final int channelId;
  final bool mute;
  final bool deaf;
  final bool selfMute;
  final bool selfDeaf;
  final bool suppress;
  final bool prioritySpeaker;
  final bool recording;
  final String comment;

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        session: j['session'] as int,
        name: (j['name'] as String?) ?? '',
        channelId: (j['channelId'] as int?) ?? 0,
        mute: (j['mute'] as bool?) ?? false,
        deaf: (j['deaf'] as bool?) ?? false,
        selfMute: (j['selfMute'] as bool?) ?? false,
        selfDeaf: (j['selfDeaf'] as bool?) ?? false,
        suppress: (j['suppress'] as bool?) ?? false,
        prioritySpeaker: (j['prioritySpeaker'] as bool?) ?? false,
        recording: (j['recording'] as bool?) ?? false,
        comment: (j['comment'] as String?) ?? '',
      );

  /// libmumble sends a *delta* in UserState messages — name is empty after the
  /// initial join, channelId is unset, etc. Merge so missing fields preserve
  /// the previously-known value.
  UserInfo merge(UserInfo other) => UserInfo(
        session: session,
        name: other.name.isNotEmpty ? other.name : name,
        channelId: other.channelId != 0 ? other.channelId : channelId,
        mute: other.mute,
        deaf: other.deaf,
        selfMute: other.selfMute,
        selfDeaf: other.selfDeaf,
        suppress: other.suppress,
        prioritySpeaker: other.prioritySpeaker,
        recording: other.recording,
        comment: other.comment.isNotEmpty ? other.comment : comment,
      );
}

class UserNotifier extends Notifier<Map<int, UserInfo>> {
  @override
  Map<int, UserInfo> build() => const {};

  void upsert(UserInfo u) {
    final existing = state[u.session];
    state = {...state, u.session: existing == null ? u : existing.merge(u)};
  }

  void remove(int session) {
    final m = {...state}..remove(session);
    state = m;
  }

  void clear() => state = const {};
}

final userProvider =
    NotifierProvider<UserNotifier, Map<int, UserInfo>>(UserNotifier.new);
