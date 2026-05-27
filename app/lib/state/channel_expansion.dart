import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks which channels the user has manually collapsed. Channels default to
/// expanded; only collapsed IDs are remembered.
class ChannelExpansionNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void toggle(int channelId) {
    final next = {...state};
    if (!next.remove(channelId)) {
      next.add(channelId);
    }
    state = next;
  }

  bool isCollapsed(int id) => state.contains(id);
}

final channelExpansionProvider =
    NotifierProvider<ChannelExpansionNotifier, Set<int>>(
        ChannelExpansionNotifier.new);
