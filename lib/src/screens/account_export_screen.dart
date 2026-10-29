import 'package:airgapped_zcash_signer/src/rust/api/vizor.dart';
import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:airgapped_zcash_signer/src/widgets/animated_ur_qr.dart';
import 'package:flutter/material.dart';

class AccountExportScreen extends StatefulWidget {
  const AccountExportScreen({super.key});

  @override
  State<AccountExportScreen> createState() => _AccountExportScreenState();
}

class _AccountExportScreenState extends State<AccountExportScreen> {
  late final Future<List<String>> _parts = _load();

  Future<List<String>> _load() async => exportTestnetAccount(
    seed: await const SeedVault().readSeed(),
    accountIndex: 0,
    name: 'Airgap phone',
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connect to Vizor')),
    body: Center(
      child: FutureBuilder<List<String>>(
        future: _parts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) return const CircularProgressIndicator();
          return ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              const Text(
                'Scan this account QR in Vizor Desktop. It contains viewing data only—never your seed.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Center(child: AnimatedUrQr(parts: snapshot.data!)),
            ],
          );
        },
      ),
    ),
  );
}
