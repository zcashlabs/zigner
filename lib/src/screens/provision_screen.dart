import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:airgapped_zcash_signer/src/theme/signer_theme.dart';
import 'package:flutter/material.dart';

class ProvisionScreen extends StatefulWidget {
  const ProvisionScreen({super.key});

  @override
  State<ProvisionScreen> createState() => _ProvisionScreenState();
}

class _ProvisionScreenState extends State<ProvisionScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _generated;

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final phrase = await const SeedVault().provisionNew();
      if (mounted) setState(() => _generated = phrase);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      await const SeedVault().importMnemonic(_controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set up testnet wallet')),
    body: SignerBackground(
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            'Create or import a recovery phrase',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'The phrase is encrypted at rest using Android Keystore. This prototype is testnet-only.',
          ),
          const SizedBox(height: 24),
          if (_generated case final phrase?) ...[
            SignerCard(
              child: SelectableText(
                phrase,
                style: const TextStyle(fontSize: 17, height: 1.6),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Write this down offline. Anyone with these words can spend the wallet.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('I saved the backup'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.add),
              label: const Text('Create new wallet'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(),
            ),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 6,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Recovery phrase',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _busy ? null : _import,
              child: const Text('Import existing wallet'),
            ),
          ],
        ],
      ),
    ),
  );
}
