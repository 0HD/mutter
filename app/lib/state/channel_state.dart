import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChannelInfo {
  ChannelInfo({
    required this.id,
    required this.name,
    this.parent,
    this.description = '',
    this.position = 0,
    this.temporary = false,
    this.maxUsers = 0,
  });

  final int id;
  final String name;
  final int? parent;
  final String description;
  final int position;
  final bool temporary;
  final int maxUsers;

  factory ChannelInfo.fromJson(Map<String, dynamic> j) => ChannelInfo(
        id: j['id'] as int,
        parent: j['parent'] as int?,
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        position: (j['position'] as int?) ?? 0,
        temporary: (j['temporary'] as bool?) ?? false,
        maxUsers: (j['maxUsers'] as int?) ?? 0,
      );

  ChannelInfo merge(ChannelInfo other) => ChannelInfo(
        id: id,
        name: other.name.isNotEmpty ? other.name : name,
        parent: other.parent ?? parent,
        description:
            other.description.isNotEmpty ? other.description : description,
        position: other.position != 0 ? other.position : position,
        temporary: other.temporary,
        maxUsers: other.maxUsers != 0 ? other.maxUsers : maxUsers,
      );
}

class ChannelNotifier extends Notifier<Map<int, ChannelInfo>> {
  @override
  Map<int, ChannelInfo> build() => const {};

  void upsert(ChannelInfo c) {
    final existing = state[c.id];
    state = {...state, c.id: existing == null ? c : existing.merge(c)};
  }

  void remove(int id) {
    final m = {...state}..remove(id);
    state = m;
  }

  void clear() => state = const {};
}

final channelProvider =
    NotifierProvider<ChannelNotifier, Map<int, ChannelInfo>>(
        ChannelNotifier.new);
