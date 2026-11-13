import 'dart:async';

import 'package:flutter/material.dart';

import '../security/seed_vault.dart';
import '../theme/signer_theme.dart';
import '../widgets/backup_quiz.dart';
import 'account_export_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.status,
    required this.onLock,
    required this.onErased,
  });
  final VaultStatus status;
  final VoidCallback onLock, onErased;
  @override
  Widget build(BuildContext context) => SignerPage(
    onBack: () => Navigator.pop(context),
    title: 'Your signer,\nyour settings.',
    children: [
      const SignerCard(
        child: InfoRow(
          icon: Icons.key_outlined,
          title: 'Main account',
          detail: 'Account 0 · Zcash Testnet',
        ),
      ),
      const SizedBox(height: 24),
      _row(
        context,
        Icons.qr_code_2_rounded,
        'Show account QR',
        'Connect viewing access to Vizor',
        () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const AccountExportScreen()),
        ),
      ),
      _row(
        context,
        Icons.fact_check_outlined,
        'Practice backup check',
        'Check three words from your paper',
        () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const PracticeBackupScreen()),
        ),
      ),
      const Divider(height: 32),
      InfoRow(
        icon: Icons.memory_outlined,
        title: 'Key storage',
        detail: status.protectionLabel,
      ),
      const InfoRow(
        icon: Icons.fingerprint_rounded,
        title: 'Unlock before every use',
        detail: 'Android authentication for signing and account export. The app locks when you leave.',
      ),
      _row(
        context,
        Icons.lock_outline_rounded,
        'Lock now',
        'Close this signer session',
        onLock,
      ),
      const Divider(height: 32),
      const InfoRow(
        icon: Icons.science_outlined,
        title: 'Zigner 1.0.0 · prototype',
        detail: 'Testnet only. No real funds.',
      ),
      _row(
        context,
        Icons.code_rounded,
        'Open-source licenses',
        'Libraries and bundled typefaces',
        () => showLicensePage(
          context: context,
          applicationName: 'Zigner',
          applicationVersion: '1.0.0 · Testnet',
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => EraseSignerScreen(onErased: onErased),
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: SignerColors.destructive,
        ),
        icon: const Icon(Icons.delete_outline_rounded),
        label: const Text('Erase signer'),
      ),
    ],
  );
  Widget _row(
    BuildContext context,
    IconData icon,
    String title,
    String detail,
    VoidCallback action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    leading: Icon(icon, color: SignerColors.mint),
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, color: SignerColors.text),
    ),
    subtitle: Text(detail, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: action,
  );
}

class PracticeBackupScreen extends StatefulWidget {
  const PracticeBackupScreen({super.key});
  @override
  State<PracticeBackupScreen> createState() => _PracticeBackupScreenState();
}

class _PracticeBackupScreenState extends State<PracticeBackupScreen>
    with WidgetsBindingObserver {
  List<BackupQuestion>? _questions;
  bool _busy = false, _complete = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        !SeedVault.authenticationInProgress) {
      unawaited(const SeedVault().discardDraft().catchError((Object _) {}));
      if (mounted) setState(() => _questions = null);
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final questions = await const SeedVault().practiceBackup();
      if (mounted) setState(() => _questions = questions);
    } catch (e) {
      if (mounted) setState(() => _error = vaultErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(const SeedVault().discardDraft().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SignerPage(
    onBack: () => Navigator.pop(context),
    title: _complete
        ? 'Your backup\nlooks right.'
        : 'Check your\npaper backup.',
    description: _complete
        ? 'All three words match. Keep your paper somewhere safe.'
        : 'Grab your paper. Zigner will ask for three words without showing the full phrase.',
    footer: _complete
        ? FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          )
        : _questions == null
        ? FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.fingerprint_rounded),
            label: Text(
              _busy ? 'Waiting for Android…' : 'Unlock to check backup',
            ),
          )
        : null,
    children: [
      if (_complete)
        const Padding(
          padding: EdgeInsets.all(40),
          child: Icon(
            Icons.check_circle_outline_rounded,
            color: SignerColors.mint,
            size: 72,
          ),
        )
      else if (_questions != null)
        BackupQuiz(
          questions: _questions!,
          onComplete: () => setState(() => _complete = true),
        )
      else
        const QuietNotice(
          'Android authentication is required to start this check. Your signer stays on this phone.',
        ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        QuietNotice(_error!, warning: true),
      ],
    ],
  );
}

class EraseSignerScreen extends StatefulWidget {
  const EraseSignerScreen({super.key, required this.onErased});
  final VoidCallback onErased;
  @override
  State<EraseSignerScreen> createState() => _EraseSignerScreenState();
}

class _EraseSignerScreenState extends State<EraseSignerScreen> {
  final _confirmation = TextEditingController();
  bool _backup = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _erase() async {
    if (!_backup || _confirmation.text != 'erase' || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await const SeedVault().erase(_confirmation.text);
      if (mounted) widget.onErased();
    } catch (e) {
      if (mounted) setState(() => _error = vaultErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SignerPage(
    onBack: _busy ? null : () => Navigator.pop(context),
    title: 'Erase this signer?',
    description: 'This removes the encryption key and signer from this phone. Recovery requires your words and any extra passphrase.',
    footer: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _backup && _confirmation.text == 'erase' && !_busy
              ? _erase
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: SignerColors.destructive,
          ),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(_busy ? 'Waiting for Android…' : 'Erase signer'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Keep signer'),
        ),
      ],
    ),
    children: [
      const QuietNotice(
        'Erasing can’t be undone. Check your paper backup before continuing.',
        warning: true,
      ),
      const SizedBox(height: 24),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'I have my recovery words and any extra passphrase backed up.',
          style: TextStyle(fontSize: 14),
        ),
        value: _backup,
        onChanged: _busy ? null : (v) => setState(() => _backup = v ?? false),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _confirmation,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Type erase to confirm'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        QuietNotice(_error!, warning: true),
      ],
    ],
  );
}
