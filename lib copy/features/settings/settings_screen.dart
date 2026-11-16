import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _url =
      TextEditingController(text: ref.read(apiClientProvider).baseUrl);
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final api = ref.read(apiClientProvider);
    await api.setBaseUrl(_url.text);
    final ok = await api.ping();
    // Drop cached feeds so they reload from the new server.
    ref.invalidate(feedProvider);
    ref.invalidate(detailProvider);
    ref.invalidate(episodesProvider);
    ref.invalidate(searchResultsProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = ok ? 'Connected ✓' : "Saved, but the server didn't answer /health";
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Backend URL', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            helperText: 'Emulator: http://10.0.2.2:8000 · Real phone: http://<PC-LAN-IP>:8000',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save & test'),
        ),
        if (_status != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_status!)),
        const Divider(height: 40),
        Text('Session: ${api.sessionId ?? 'not created yet'}',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            await api.resetSession();
            setState(() => _status = 'Session reset. A new one is created on the next request.');
          },
          child: const Text('Reset session'),
        ),
      ]),
    );
  }
}
