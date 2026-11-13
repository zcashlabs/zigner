import 'package:flutter/material.dart';

import '../rust/api/vizor.dart';
import '../security/seed_vault.dart';
import '../theme/signer_theme.dart';
import '../widgets/animated_ur_qr.dart';

class AccountExportScreen extends StatefulWidget {
  const AccountExportScreen({super.key});
  @override
  State<AccountExportScreen> createState() => _AccountExportScreenState();
}

class _AccountExportScreenState extends State<AccountExportScreen> {
  late Future<List<String>> _parts = _load();
  Future<List<String>> _load() async {
    final seed = await const SeedVault().readSeed();
    try {
      if (!mounted) return [];
      return exportTestnetAccount(seed: seed, accountIndex: 0, name: 'Zigner');
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) => SignerPage(
    onBack: () => Navigator.pop(context),
    title: 'Let Vizor scan\nthis code.',
    description: 'On your computer, add an air-gapped signer in Vizor and scan the animated QR.',
    footer: FilledButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Vizor has it, done'),
    ),
    children: [
      FutureBuilder<List<String>>(
        future: _parts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                QuietNotice(vaultErrorMessage(snapshot.error!), warning: true),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => setState(() => _parts = _load()),
                  child: const Text('Try again'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Center(child: AnimatedUrQr(parts: snapshot.data!));
        },
      ),
      const SizedBox(height: 28),
      const SignerCard(
        child: InfoRow(
          icon: Icons.visibility_outlined,
          title: 'Viewing access only',
          detail: 'This QR lets Vizor view your account. It doesn’t contain your recovery phrase or spending keys. Share it only with a wallet you trust.',
        ),
      ),
    ],
  );
}
