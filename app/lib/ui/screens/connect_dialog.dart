import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_service.dart';
import '../../bridge/lan_discovery.dart';
import '../../settings/app_settings.dart';
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
  final _favName = TextEditingController();
  bool _saveAsFavorite = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the username with what was used last time.
    _username.text = ref.read(settingsProvider).lastUsername;
    for (final c in [_host, _port, _username, _password, _favName]) {
      c.addListener(_onChange);
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _username, _password, _favName]) {
      c.removeListener(_onChange);
      c.dispose();
    }
    super.dispose();
  }

  void _applyFavorite(ServerFavorite f) {
    _host.text = f.host;
    _port.text = f.port.toString();
    _username.text = f.username;
    _favName.text = f.name;
    _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(settingsProvider).favorites;
    final lan = ref.watch(lanDiscoveryProvider);
    return Dialog(
      backgroundColor: AppColors.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarList(
              favorites: favorites,
              lanServers: lan,
              onPickFavorite: _applyFavorite,
              onPickLan: (s) => _applyFavorite(ServerFavorite(
                name: s.displayName,
                host: s.address,
                port: s.port,
              )),
              onRemoveFavorite: (f) {
                final notifier = ref.read(settingsProvider.notifier);
                notifier.update((s) => s.copyWith(
                      favorites: s.favorites.where((x) => x != f).toList(),
                    ));
              },
              onRescanLan: () => ref
                  .read(lanDiscoveryProvider.notifier)
                  .scan(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Connect to server',
                      style: TextStyle(
                          color: AppColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1),
                    ),
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 12),
                    _Field(
                        label: 'Username',
                        controller: _username,
                        hint: 'your-name'),
                    const SizedBox(height: 12),
                    _Field(
                        label: 'Server password (optional)',
                        controller: _password,
                        obscure: true),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Checkbox(
                          value: _saveAsFavorite,
                          onChanged: (v) =>
                              setState(() => _saveAsFavorite = v ?? false),
                        ),
                        const SizedBox(width: 4),
                        const Text('Save as favorite',
                            style: TextStyle(
                                color: AppColors.textDim, fontSize: 12.5)),
                      ],
                    ),
                    if (_saveAsFavorite)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _Field(
                          label: 'Favorite name',
                          controller: _favName,
                          hint: _host.text.isEmpty ? 'My server' : _host.text,
                        ),
                      ),
                    const Spacer(),
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
          ],
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
    final host = _host.text.trim();
    final port = int.parse(_port.text);
    final username = _username.text.trim();

    if (_saveAsFavorite) {
      final notifier = ref.read(settingsProvider.notifier);
      final name = _favName.text.trim().isNotEmpty ? _favName.text.trim() : host;
      final fav = ServerFavorite(
          name: name, host: host, port: port, username: username);
      notifier.update((s) => s.copyWith(
            favorites: [...s.favorites.where((f) => f.host != host || f.port != port), fav],
          ));
    }

    // Remember the username for next time.
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(lastUsername: username));

    bridge.connect(
      host: host,
      port: port,
      username: username,
      password: _password.text.isEmpty ? null : _password.text,
    );
    Navigator.of(context).pop();
  }
}

class _SidebarList extends StatelessWidget {
  const _SidebarList({
    required this.favorites,
    required this.lanServers,
    required this.onPickFavorite,
    required this.onPickLan,
    required this.onRemoveFavorite,
    required this.onRescanLan,
  });

  final List<ServerFavorite> favorites;
  final List<LanServer> lanServers;
  final void Function(ServerFavorite) onPickFavorite;
  final void Function(LanServer) onPickLan;
  final void Function(ServerFavorite) onRemoveFavorite;
  final VoidCallback onRescanLan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppColors.bg1,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _SectionHeading(
            label: 'On your network',
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 14),
              tooltip: 'Rescan',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
              onPressed: onRescanLan,
            ),
          ),
          if (lanServers.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'No Mumble servers found on the LAN.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            )
          else
            for (final s in lanServers)
              _LanRow(server: s, onTap: () => onPickLan(s)),
          const SizedBox(height: 8),
          const _SectionHeading(label: 'Favorites'),
          if (favorites.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'No favorites yet. Tick "Save as favorite" when connecting.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            )
          else
            for (final f in favorites)
              _FavoriteRow(
                favorite: f,
                onTap: () => onPickFavorite(f),
                onRemove: () => onRemoveFavorite(f),
              ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label, this.trailing});
  final String label;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _LanRow extends StatefulWidget {
  const _LanRow({required this.server, required this.onTap});
  final LanServer server;
  final VoidCallback onTap;
  @override
  State<_LanRow> createState() => _LanRowState();
}

class _LanRowState extends State<_LanRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hover ? AppColors.bg2 : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.lan_rounded,
                  size: 13, color: AppColors.textMuted.withValues(alpha: 0.9)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.server.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(
                      '${widget.server.address}:${widget.server.port}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteRow extends StatefulWidget {
  const _FavoriteRow({
    required this.favorite,
    required this.onTap,
    required this.onRemove,
  });
  final ServerFavorite favorite;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_FavoriteRow> createState() => _FavoriteRowState();
}

class _FavoriteRowState extends State<_FavoriteRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hover ? AppColors.bg2 : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.favorite.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${widget.favorite.host}:${widget.favorite.port}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (_hover)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: widget.onRemove,
                ),
            ],
          ),
        ),
      ),
    );
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
