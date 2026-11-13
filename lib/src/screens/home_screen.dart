import 'package:flutter/material.dart';

import '../rust/api/vizor.dart';
import '../security/seed_vault.dart';
import '../theme/signer_theme.dart';
import 'account_export_screen.dart';
import 'qr_scanner_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.vaultStatus,
    required this.onLock,
    required this.onErased,
  });
  final VaultStatus vaultStatus;
  final VoidCallback onLock, onErased;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  late VaultStatus _status = widget.vaultStatus;
  Future<void> _scan() async {
    final payload = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (payload == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final review = inspectVizorBatch(cbor: payload);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(review: review, cbor: payload),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => RequestRejectedScreen(reason: '$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          status: _status,
          onLock: widget.onLock,
          onErased: widget.onErased,
        ),
      ),
    );
    if (mounted) {
      final status = await const SeedVault().status();
      if (mounted) setState(() => _status = status);
    }
  }

  @override
  Widget build(BuildContext context) => SignerPage(
    header: Row(
      children: [
        const Expanded(child: ZignerBrand()),
        IconButton(
          onPressed: _busy ? null : _settings,
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    title: 'All quiet.\nReady when you are.',
    description:
        'Check every payment here before your signature leaves this phone.',
    children: [
      const Row(
        children: [
          Icon(Icons.key_outlined, size: 16, color: SignerColors.mint),
          SizedBox(width: 8),
          Text('Main account', style: TextStyle(fontSize: 14)),
          Spacer(),
          TestnetBadge(),
        ],
      ),
      const SizedBox(height: 28),
      Material(
        color: SignerColors.mintSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: SignerColors.mint.withValues(alpha: .4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : _scan,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: SignerColors.mint,
                  size: 40,
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _busy ? 'Checking request…' : 'Scan a request',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontSize: 22),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: SignerColors.mint,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Point this phone at the animated QR in Vizor.',
                  style: TextStyle(fontSize: 14, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const AccountExportScreen()),
              ),
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('Show account QR'),
      ),
      const SizedBox(height: 36),
      const Text(
        'THIS PHONE',
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip(
            _status.internetPermission
                ? Icons.developer_mode
                : Icons.wifi_off_rounded,
            _status.internetPermission
                ? 'Dev connection'
                : 'No network permission',
            warning: _status.internetPermission,
          ),
          _chip(
            Icons.memory_rounded,
            _status.protection == 'strongbox'
                ? 'StrongBox key'
                : 'Hardware key',
          ),
          _chip(
            _status.backupChecked
                ? Icons.check_circle_outline
                : Icons.edit_note_rounded,
            _status.backupChecked ? 'Backup checked' : 'Backup not checked',
            warning: !_status.backupChecked,
          ),
        ],
      ),
      const SizedBox(height: 24),
      const QuietNotice(
        'Early testnet prototype. Don’t use it for real funds.',
        warning: true,
      ),
    ],
  );
  Widget _chip(IconData icon, String label, {bool warning = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: warning ? SignerColors.goldSoft : SignerColors.surface,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: warning ? SignerColors.gold : SignerColors.mint,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: warning ? SignerColors.gold : SignerColors.textMuted,
              ),
            ),
          ],
        ),
      );
}

class RequestRejectedScreen extends StatelessWidget {
  const RequestRejectedScreen({super.key, required this.reason});
  final String reason;
  @override
  Widget build(BuildContext context) => SignerPage(
    onBack: () => Navigator.pop(context),
    title: 'This request\ncan’t be signed.',
    description: 'Your signer hasn’t signed anything. Check the request in Vizor and try again.',
    footer: FilledButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Back to home'),
    ),
    children: [
      const Padding(
        padding: EdgeInsets.all(24),
        child: Icon(
          Icons.info_outline_rounded,
          size: 64,
          color: SignerColors.gold,
        ),
      ),
      QuietNotice(reason, warning: true),
    ],
  );
}
