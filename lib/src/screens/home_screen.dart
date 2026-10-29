import 'package:airgapped_zcash_signer/src/rust/api/vizor.dart';
import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:airgapped_zcash_signer/src/screens/account_export_screen.dart';
import 'package:airgapped_zcash_signer/src/screens/provision_screen.dart';
import 'package:airgapped_zcash_signer/src/screens/qr_scanner_screen.dart';
import 'package:airgapped_zcash_signer/src/screens/review_screen.dart';
import 'package:airgapped_zcash_signer/src/theme/signer_theme.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  bool _provisioned = false;

  @override
  void initState() {
    super.initState();
    _refreshProvisioning();
  }

  Future<void> _refreshProvisioning() async {
    final value = await const SeedVault().isProvisioned;
    if (mounted) setState(() => _provisioned = value);
  }

  Future<void> _scan() async {
    final payload = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (payload != null && mounted) await _inspect(payload);
  }

  Future<void> _inspect(List<int> payload) async {
    setState(() => _busy = true);
    try {
      final review = inspectVizorBatch(cbor: payload);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(review: review, cbor: payload),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SignerBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD96B), SignerColors.gold],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: SignerColors.background,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ZCASH SIGNER',
                          style: TextStyle(
                            color: SignerColors.text,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Offline signing device',
                          style: TextStyle(
                            color: SignerColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _OfflineBadge(),
                ],
              ),
              const SizedBox(height: 48),
              const Text(
                'SECURE SESSION  ·  TESTNET',
                style: TextStyle(
                  color: SignerColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your keys stay here.\nYour intent stays clear.',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Scan a request, verify every detail, then return the signed response—without exposing your secrets.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 30),
              SignerCard(
                child: Column(
                  children: [
                    _StatusRow(
                      icon: Icons.wifi_off_rounded,
                      title: 'Airgap ready',
                      detail: 'Release networking disabled',
                      positive: true,
                    ),
                    Divider(height: 30, color: SignerColors.border),
                    _StatusRow(
                      icon: _provisioned
                          ? Icons.key_rounded
                          : Icons.vpn_key_off_rounded,
                      title: _provisioned
                          ? 'Testnet key ready'
                          : 'Wallet not set up',
                      detail: _provisioned
                          ? 'Seed encrypted with Android Keystore'
                          : 'Create or import a testnet wallet',
                      positive: _provisioned,
                    ),
                    Divider(height: 30, color: SignerColors.border),
                    _StatusRow(
                      icon: Icons.verified_user_rounded,
                      title: 'Policy engine active',
                      detail: 'Rust validation is enforcing limits',
                      positive: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy || !_provisioned ? null : _scan,
                icon: const Icon(Icons.center_focus_strong_rounded),
                label: Text(_busy ? 'Inspecting…' : 'Scan Vizor request'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!_provisioned) {
                          await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => const ProvisionScreen(),
                            ),
                          );
                          await _refreshProvisioning();
                        } else {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const AccountExportScreen(),
                            ),
                          );
                        }
                      },
                icon: Icon(
                  _provisioned ? Icons.qr_code_2 : Icons.add_circle_outline,
                ),
                label: Text(
                  _provisioned
                      ? 'Connect to Vizor Desktop'
                      : 'Set up testnet wallet',
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'TESTNET ONLY  /  OFFLINE SIGNER',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SignerColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF14271F),
        border: Border.all(color: const Color(0xFF24503C)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: SignerColors.mint),
          SizedBox(width: 6),
          Text(
            'OFFLINE',
            style: TextStyle(
              color: SignerColors.mint,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.positive = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: positive
                ? const Color(0xFF14271F)
                : SignerColors.surfaceRaised,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            size: 20,
            color: positive ? SignerColors.mint : SignerColors.textMuted,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
