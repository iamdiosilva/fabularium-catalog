import 'dart:async';

import 'package:flutter/material.dart';

import '../services/telegram_service.dart';
import 'telegram_group_pages.dart';
import 'telegram_storage_page.dart';

class TelegramLoginPage extends StatefulWidget {
  const TelegramLoginPage({super.key});
  @override
  State<TelegramLoginPage> createState() => _TelegramLoginPageState();
}

class _TelegramLoginPageState extends State<TelegramLoginPage> {
  final TelegramService _telegram = TelegramService.instance;
  final _phone = TextEditingController(text: '+55');
  final _code = TextEditingController();
  final _password = TextEditingController();
  StreamSubscription<TelegramAuthState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _telegram.stateStream.listen((_) { if (mounted) setState(() {}); });
    _telegram.connect();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _phone.dispose(); _code.dispose(); _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Telegram')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _buildState(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildState() {
    switch (_telegram.state) {
      case TelegramAuthState.connecting:
        return const Center(child: CircularProgressIndicator());
      case TelegramAuthState.phoneRequired:
      case TelegramAuthState.disconnected:
        return _form('Phone Number', _phone, 'Send Code', () => _telegram.sendCode(_phone.text));
      case TelegramAuthState.codeRequired:
        return _form('Verification Code', _code, 'Sign In', () => _telegram.signIn(_code.text));
      case TelegramAuthState.passwordRequired:
        return _form('Two-Step Verification Password', _password, 'Continue', () => _telegram.checkPassword(_password.text), obscure: true);
      case TelegramAuthState.authenticated:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('Telegram account authenticated.', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TelegramGroupPages())),
            icon: const Icon(Icons.groups_outlined), label: const Text('Browse Groups'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TelegramStoragePage())),
            icon: const Icon(Icons.cloud_outlined), label: const Text('Telegram Storage'),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: () async { await _telegram.logout(); if (mounted) setState(() {}); }, child: const Text('Log Out')),
        ]);
      case TelegramAuthState.error:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_telegram.errorMessage ?? 'Telegram error.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: _telegram.connect, child: const Text('Try Again')),
        ]);
    }
  }

  Widget _form(String label, TextEditingController controller, String button, Future<void> Function() action, {bool obscure = false}) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      TextField(controller: controller, obscureText: obscure, onSubmitted: (_) => action(), decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton(onPressed: action, child: Text(button)),
    ]);
  }
}
