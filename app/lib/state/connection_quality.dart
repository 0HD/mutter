import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connection quality stats — sent by the server inside Ping responses.
/// All ping values are milliseconds. Packet counts are cumulative since the
/// connection opened.
class ConnectionQuality {
  const ConnectionQuality({
    this.tcpPingMs = 0.0,
    this.udpPingMs = 0.0,
    this.good = 0,
    this.late = 0,
    this.lost = 0,
    this.resync = 0,
  });

  final double tcpPingMs;
  final double udpPingMs;
  final int good;
  final int late;
  final int lost;
  final int resync;

  bool get hasData => tcpPingMs > 0 || udpPingMs > 0 || (good + late + lost) > 0;

  /// Packet loss as a fraction in [0,1]. Returns 0 if no packets seen.
  double get lossRatio {
    final total = good + late + lost;
    if (total == 0) return 0.0;
    return lost / total;
  }
}

class ConnectionQualityNotifier extends Notifier<ConnectionQuality> {
  @override
  ConnectionQuality build() => const ConnectionQuality();

  void update(Map<String, dynamic> j) {
    state = ConnectionQuality(
      tcpPingMs: (j['tcpPingAvg'] as num?)?.toDouble() ?? 0.0,
      udpPingMs: (j['udpPingAvg'] as num?)?.toDouble() ?? 0.0,
      good: (j['good'] as int?) ?? 0,
      late: (j['late'] as int?) ?? 0,
      lost: (j['lost'] as int?) ?? 0,
      resync: (j['resync'] as int?) ?? 0,
    );
  }

  void reset() => state = const ConnectionQuality();
}

final connectionQualityProvider =
    NotifierProvider<ConnectionQualityNotifier, ConnectionQuality>(
        ConnectionQualityNotifier.new);
