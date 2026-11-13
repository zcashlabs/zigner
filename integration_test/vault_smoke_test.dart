import 'package:airgapped_zcash_signer/src/app.dart';
import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:airgapped_zcash_signer/src/rust/frb_generated.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);

  testWidgets(
    'verifies real hardware protection and renders without unlocking a seed',
    (tester) async {
      final status = await const SeedVault().status();
      expect(status.ready, true, reason: status.error);
      expect(status.protection, anyOf('strongbox', 'tee'));
      // Only non-secret capability information is printed; no existing signer is read or replaced.
      // ignore: avoid_print
      print(
        'Vault hardware: ${status.protection}; existing signer: ${status.hasSigner}; legacy: ${status.hasLegacySigner}',
      );
      if (const bool.fromEnvironment('REQUIRE_DEVICE_UI')) {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (tester.binding.lifecycleState != AppLifecycleState.resumed &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(
          tester.binding.lifecycleState,
          AppLifecycleState.resumed,
          reason: 'Unlock the phone and leave Zigner in the foreground to run device UI assertions.',
        );
      }
      // A locked phone suspends Flutter frames. Capability verification above still
      // works; UI behavior is also covered by host widget tests.
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        // ignore: avoid_print
        print(
          'Device UI assertions skipped: phone is locked or app is not in the foreground.',
        );
        return;
      }
      await tester.pumpWidget(const SignerApp());
      await tester.pumpAndSettle();
      expect(find.text('Zigner'), findsOneWidget);
      if (!status.hasSigner && !status.hasLegacySigner) {
        expect(find.text('Get started'), findsOneWidget);
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();
        expect(find.text(status.protectionLabel), findsOneWidget);
        expect(
          find.text(
            status.internetPermission
                ? 'Development connection enabled'
                : 'No app network permission',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Create a new signer'), findsOneWidget);
        expect(find.text('I have a recovery phrase'), findsOneWidget);
      } else if (!status.hasLegacySigner) {
        expect(find.text('Unlock to open signer'), findsOneWidget);
      }
    },
  );
}
