import 'dart:async';

import 'package:airgapped_zcash_signer/src/app.dart';
import 'package:airgapped_zcash_signer/src/rust/frb_generated.dart';
import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Run only in the separate .vault_test debug application. The public BIP-39
// vector below must never be used in the ordinary app or for funds.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);
  testWidgets('real StrongBox authentication saves and reads the correct seed', (
    tester,
  ) async {
    final identity = await SeedVault.channel.invokeMethod<String>(
      'selfTestApplicationId',
    );
    expect(
      identity,
      'org.zcash.airgap.airgapped_zcash_signer.vault_test',
      reason: 'Run with ORG_GRADLE_PROJECT_zignerVaultSelfTest=true to isolate the test from the user vault.',
    );
    final before = await const SeedVault().status();
    expect(
      before.hasSigner,
      false,
      reason: 'Use a fresh isolated self-test installation.',
    );
    expect(before.hasLegacySigner, false);
    expect(before.ready, true, reason: before.error);
    expect(before.protection, anyOf('strongbox', 'tee'));
    await tester.pumpWidget(const SignerApp());
    await tester.pumpAndSettle();
    Future<void> tap(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    Future<void> until(bool Function() done, String phase) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        // Let Android deliver its authentication result while the app is inactive.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(
        done(),
        true,
        reason:
            '$phase needs Android fingerprint or device-credential authentication.',
      );
    }

    await tap('Get started');
    await tap('Continue');
    await tap('I have a recovery phrase');
    await tester.enterText(
      find.byType(TextField),
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    );
    await until(
      () =>
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Continue'),
              )
              .onPressed !=
          null,
      'Phrase validation',
    );
    await tap('Continue');
    await tap('I used an extra passphrase');
    await tester.enterText(find.byType(TextField).at(0), 'TREZOR');
    await tester.enterText(find.byType(TextField).at(1), 'TREZOR');
    await tap('Continue with passphrase');
    // Avoid pumpAndSettle here: the app waits on a real system authentication.
    await tester.tap(find.text('Unlock to protect'));
    // ignore: avoid_print
    print(
      'SELF_TEST_SAVE_PROMPT: authenticate on the Pixel to save the isolated public test vector.',
    );
    await until(
      () => find.text('Your signer\nis ready.').evaluate().isNotEmpty,
      'Saving the signer',
    );
    final saved = await const SeedVault().status();
    expect(saved.hasSigner, true);
    expect(
      saved.backupChecked,
      false,
    ); // Import is not a paper-backup verification.
    // ignore: avoid_print
    print(
      'SELF_TEST_SAVE_PASSED: ${saved.protection}. A second Android prompt verifies decryption.',
    );
    Uint8List? seed;
    Object? readError;
    var readDone = false;
    unawaited(
      const SeedVault().readSeed().then(
        (value) {
          seed = value;
          readDone = true;
        },
        onError: (Object e) {
          readError = e;
          readDone = true;
        },
      ),
    );
    await until(() => readDone, 'Reading the saved signer');
    expect(
      readError,
      isNull,
      reason: 'Authenticated decryption must succeed after saving.',
    );
    final expected =
        'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04';
    try {
      expect(
        seed,
        orderedEquals([
          for (var i = 0; i < expected.length; i += 2)
            int.parse(expected.substring(i, i + 2), radix: 16),
        ]),
      );
    } finally {
      seed?.fillRange(0, seed!.length, 0);
    }
    // ignore: avoid_print
    print(
      'SELF_TEST_ROUND_TRIP_PASSED: authenticated AES-GCM save/read matches the public BIP-39 vector.',
    );
  });
}
