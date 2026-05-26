import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Most recent mic input RMS in [0, 1], updated ~20 times per second by the
/// native audio engine. The provider just stores the latest value; widgets
/// that show a level meter watch it and rebuild.
class AudioLevelNotifier extends Notifier<double> {
  @override
  double build() => 0.0;

  void set(double rms) {
    state = rms;
  }
}

final audioLevelProvider =
    NotifierProvider<AudioLevelNotifier, double>(AudioLevelNotifier.new);
