import 'package:flutter/material.dart';

import '../../state/connection_state.dart';
import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.phase,
    this.errorMessage,
    required this.onConnect,
  });

  final ConnectionPhase phase;
  final String? errorMessage;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.graphic_eq_rounded,
                  size: 38, color: AppColors.accent),
              const SizedBox(height: 18),
              const Text(
                'mutter',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitleFor(phase, errorMessage),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 13,
                    height: 1.5,
                    letterSpacing: 0.1),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Connect to a server'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleFor(ConnectionPhase p, String? err) => switch (p) {
        ConnectionPhase.error =>
          err ?? 'Connection failed. Check the host and try again.',
        ConnectionPhase.connecting => 'Connecting…',
        ConnectionPhase.authenticating => 'Authenticating…',
        ConnectionPhase.synchronizing => 'Synchronizing channel list…',
        _ =>
          'Connect to a Mumble server to talk with your friends. '
              'Your settings are stored locally.',
      };
}
