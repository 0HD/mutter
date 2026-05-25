import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_service.dart';
import '../theme/app_theme.dart';

class ConnectDialog extends ConsumerStatefulWidget {
  const ConnectDialog({super.key});

  @override
  ConsumerState<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends ConsumerState<ConnectDialog> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '64738');
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_host, _port, _username, _password]) {
      c.addListener(_onChange);
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _username, _password]) {
      c.removeListener(_onChange);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Connect to server',
                style: TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: _Field(
                          label: 'Host',
                          controller: _host,
                          hint: 'mumble.example.com')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _Field(
                          label: 'Port',
                          controller: _port,
                          hint: '64738',
                          keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 14),
              _Field(
                  label: 'Username',
                  controller: _username,
                  hint: 'your-name'),
              const SizedBox(height: 14),
              _Field(
                  label: 'Server password (optional)',
                  controller: _password,
                  obscure: true),
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppColors.textDim)),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _canSubmit() ? _onConnect : null,
                    child: const Text('Connect'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canSubmit() =>
      _host.text.trim().isNotEmpty &&
      _username.text.trim().isNotEmpty &&
      (int.tryParse(_port.text) ?? -1) > 0;

  void _onConnect() {
    final bridge = ref.read(bridgeProvider);
    bridge.connect(
      host: _host.text.trim(),
      port: int.parse(_port.text),
      username: _username.text.trim(),
      password: _password.text.isEmpty ? null : _password.text,
    );
    Navigator.of(context).pop();
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w500)),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hint),
          style: const TextStyle(fontSize: 14, color: AppColors.text),
        ),
      ],
    );
  }
}
