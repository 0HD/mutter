import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_service.dart';
import '../../state/connection_state.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_panel.dart';
import '../widgets/empty_state.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';
import 'connect_dialog.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure the bridge is initialized as soon as the UI mounts.
    ref.watch(bridgeProvider);
    final conn = ref.watch(connectionProvider);

    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: Column(
        children: [
          const TopBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Sidebar(),
                const VerticalDivider(width: 1),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: conn.isConnected
                        ? const _ConnectedWorkspace()
                        : EmptyState(
                            key: const ValueKey('empty'),
                            phase: conn.phase,
                            errorMessage: conn.errorMessage,
                            onConnect: () => _openConnectDialog(context),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openConnectDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: const Color(0xAA000000),
      builder: (_) => const ConnectDialog(),
    );
  }
}

class _ConnectedWorkspace extends StatelessWidget {
  const _ConnectedWorkspace();

  @override
  Widget build(BuildContext context) {
    return const ChatPanel(key: ValueKey('connected'));
  }
}
