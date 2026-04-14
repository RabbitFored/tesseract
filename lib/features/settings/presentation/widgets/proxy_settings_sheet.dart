import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../downloader/data/download_manager.dart';
import '../../data/settings_controller.dart';
import '../../domain/settings_state.dart';

/// Bottom sheet for configuring SOCKS5 / MTProto proxy.
class ProxySettingsSheet extends StatefulWidget {
  const ProxySettingsSheet({
    super.key,
    required this.settings,
    required this.controller,
  });

  final SettingsState settings;
  final SettingsController controller;

  @override
  State<ProxySettingsSheet> createState() => _ProxySettingsSheetState();
}

class _ProxySettingsSheetState extends State<ProxySettingsSheet> {
  late bool _enabled;
  late ProxyType _type;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _secret;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _enabled = s.proxyEnabled;
    _type = s.proxyType == ProxyType.none ? ProxyType.socks5 : s.proxyType;
    _host = TextEditingController(text: s.proxyHost);
    _port = TextEditingController(text: s.proxyPort.toString());
    _user = TextEditingController(text: s.proxyUsername);
    _pass = TextEditingController(text: s.proxyPassword);
    _secret = TextEditingController(text: s.proxySecret);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Proxy Settings',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Enable Proxy'),
              value: _enabled,
              activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
              activeThumbColor: const Color(0xFF2AABEE),
              onChanged: (v) => setState(() => _enabled = v),
              contentPadding: EdgeInsets.zero,
            ),

            if (_enabled) ...[
              const SizedBox(height: 12),
              SegmentedButton<ProxyType>(
                segments: const [
                  ButtonSegment(
                    value: ProxyType.socks5,
                    label: Text('SOCKS5'),
                    icon: Icon(Icons.security_rounded),
                  ),
                  ButtonSegment(
                    value: ProxyType.mtproto,
                    label: Text('MTProto'),
                    icon: Icon(Icons.vpn_key_rounded),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) =>
                    setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _host,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        hintText: '127.0.0.1',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '1080',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_type == ProxyType.socks5) ...[
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(
                    labelText: 'Username (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],

              if (_type == ProxyType.mtproto) ...[
                TextField(
                  controller: _secret,
                  decoration: const InputDecoration(
                    labelText: 'Secret (hex)',
                    hintText: 'dd...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    await widget.controller.setProxyEnabled(_enabled);
    if (_enabled) {
      await widget.controller.setProxyConfig(
        type: _type,
        host: _host.text.trim(),
        port: int.tryParse(_port.text) ?? 1080,
        username: _user.text.trim(),
        password: _pass.text,
        secret: _secret.text.trim(),
      );
    }
    // Re-apply proxy to TDLib immediately so the change takes effect
    // without requiring an app restart.
    if (mounted) {
      final manager = ProviderScope.containerOf(context)
          .read(downloadManagerProvider);
      await manager.reapplyProxy();
    }
    if (mounted) Navigator.pop(context);
  }
}
