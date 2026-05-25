import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionPhase {
  disconnected,
  connecting,
  authenticating,
  synchronizing,
  connected,
  error,
}

class ConnectionState {
  const ConnectionState({
    this.phase = ConnectionPhase.disconnected,
    this.host,
    this.username,
    this.errorMessage,
    this.welcomeText,
    this.sessionId,
  });

  final ConnectionPhase phase;
  final String? host;
  final String? username;
  final String? errorMessage;
  final String? welcomeText;
  final int? sessionId;

  bool get isConnected => phase == ConnectionPhase.connected;
  bool get isBusy =>
      phase == ConnectionPhase.connecting ||
      phase == ConnectionPhase.authenticating ||
      phase == ConnectionPhase.synchronizing;

  ConnectionState copyWith({
    ConnectionPhase? phase,
    String? host,
    String? username,
    String? errorMessage,
    String? welcomeText,
    int? sessionId,
  }) {
    return ConnectionState(
      phase: phase ?? this.phase,
      host: host ?? this.host,
      username: username ?? this.username,
      errorMessage: errorMessage,
      welcomeText: welcomeText ?? this.welcomeText,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}

class ConnectionNotifier extends Notifier<ConnectionState> {
  @override
  ConnectionState build() => const ConnectionState();

  void setPhase(ConnectionPhase phase, {String? error, String? welcome}) {
    state = state.copyWith(
        phase: phase, errorMessage: error, welcomeText: welcome);
  }

  void setIdentity(String host, String username) {
    state = state.copyWith(host: host, username: username);
  }

  void setSession(int session) {
    state = state.copyWith(sessionId: session);
  }

  void disconnected() {
    state = const ConnectionState();
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnectionState>(
        ConnectionNotifier.new);
