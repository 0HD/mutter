import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// A Mumble server announcing itself on the LAN via mDNS.
class LanServer {
  const LanServer({
    required this.host,
    required this.address,
    required this.port,
    this.serviceName,
  });
  final String host;          // mDNS target hostname (e.g. murmur.local)
  final String address;       // resolved IPv4 / IPv6 string
  final int port;
  final String? serviceName;  // human-readable service instance name, if any

  String get displayName =>
      serviceName?.isNotEmpty == true ? serviceName! : host;
}

/// Browses for `_mumble._tcp.local` services on the local network. Mumble's
/// official client uses the same service type, and Murmur publishes it when
/// configured. We refresh periodically so users joining the LAN show up.
class LanDiscoveryNotifier extends Notifier<List<LanServer>> {
  Timer? _timer;
  bool _running = false;

  @override
  List<LanServer> build() {
    // Kick off a first scan and then keep refreshing.
    Future.microtask(scan);
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => scan());
    ref.onDispose(() => _timer?.cancel());
    return const [];
  }

  Future<void> scan() async {
    if (_running) return;
    _running = true;
    final discovered = <String, LanServer>{};
    final client = MDnsClient();
    try {
      await client.start();
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_mumble._tcp.local'),
        timeout: const Duration(seconds: 3),
      )) {
        await for (final SrvResourceRecord srv
            in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: const Duration(seconds: 2),
        )) {
          await for (final IPAddressResourceRecord ip
              in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 2),
          )) {
            final key = '${ip.address.address}:${srv.port}';
            discovered[key] = LanServer(
              host: srv.target,
              address: ip.address.address,
              port: srv.port,
              serviceName: _instanceLabel(ptr.domainName),
            );
          }
        }
      }
    } catch (_) {
      // Multicast not available, blocked by firewall, etc. Silent fail.
    } finally {
      client.stop();
      _running = false;
    }
    state = discovered.values.toList(growable: false);
  }

  /// `_mumble._tcp.local` PTR records point at "InstanceName._mumble._tcp.local"
  /// where InstanceName is the human-readable label.
  static String? _instanceLabel(String domainName) {
    final dot = domainName.indexOf('.');
    if (dot <= 0) return null;
    return domainName.substring(0, dot);
  }
}

final lanDiscoveryProvider =
    NotifierProvider<LanDiscoveryNotifier, List<LanServer>>(
        LanDiscoveryNotifier.new);
