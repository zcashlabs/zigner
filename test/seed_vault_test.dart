import 'package:airgapped_zcash_signer/src/app.dart';
import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _legacyKey = 'zcash_testnet_mnemonic_v1';
const _walletKey = 'zcash_testnet_wallet_v1';
const _vault = SeedVault();

class _FailingStorage extends FlutterSecureStorage {
  bool failWrites = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrites) throw StateError('Write failed');
    await super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 30,
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _restart(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SignerApp());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('new wallet stays unprovisioned until backup is confirmed', () async {
    final phrase = await _vault.provisionNew();
    expect(bip39.validateMnemonic(phrase), isTrue);
    expect(phrase.split(' '), hasLength(24));
    expect(await _vault.status, WalletStatus.backupPending);
    expect(await const SeedVault().readMnemonicForBackup(), phrase);
    expect(await _vault.isProvisioned, isFalse);
    await expectLater(_vault.readSeed(), throwsStateError);
    await _vault.confirmBackup();
    expect(await const SeedVault().status, WalletStatus.ready);
    expect(await _vault.readSeed(), bip39.mnemonicToSeed(phrase));
    await _vault.confirmBackup();
    expect(await _vault.readMnemonicForBackup(), phrase);
  });

  test('concurrent creation resumes one pending wallet', () async {
    final phrases = await Future.wait(
      List.generate(5, (_) => const SeedVault().provisionNew()),
    );
    expect(phrases.toSet(), hasLength(1));
    expect(await _vault.provisionNew(), phrases.first);
  });

  test(
    'import restores an existing backup without replacing another wallet',
    () async {
      await _vault.importMnemonic(
        '  ${_mnemonic.toUpperCase().replaceAll(' ', '  ')}  ',
      );
      expect(await _vault.status, WalletStatus.ready);
      expect(await _vault.readSeed(), bip39.mnemonicToSeed(_mnemonic));
      await expectLater(_vault.provisionNew(), throwsStateError);
      await expectLater(
        _vault.importMnemonic(bip39.generateMnemonic()),
        throwsStateError,
      );
      expect(await _vault.readMnemonicForBackup(), _mnemonic);
    },
  );

  test('pending wallet cannot be replaced by an import', () async {
    final phrase = await _vault.provisionNew();
    await expectLater(_vault.importMnemonic(_mnemonic), throwsStateError);
    expect(await _vault.readMnemonicForBackup(), phrase);
    expect(await _vault.status, WalletStatus.backupPending);
  });

  test(
    'legacy wallet requires confirmation and retains its original seed',
    () async {
      FlutterSecureStorage.setMockInitialValues({_legacyKey: _mnemonic});
      expect(await _vault.status, WalletStatus.backupPending);
      expect(await _vault.provisionNew(), _mnemonic);
      await expectLater(_vault.readSeed(), throwsStateError);
      await _vault.confirmBackup();
      expect(await const SeedVault().status, WalletStatus.ready);
      expect(await _vault.readSeed(), bip39.mnemonicToSeed(_mnemonic));
      await _vault.delete();
      expect(await _vault.status, WalletStatus.empty);
      expect(await const FlutterSecureStorage().read(key: _legacyKey), isNull);
      expect(await const FlutterSecureStorage().read(key: _walletKey), isNull);
    },
  );

  test(
    'failed confirmation keeps the same wallet pending and can be retried',
    () async {
      final storage = _FailingStorage();
      final vault = SeedVault(storage);
      final phrase = await vault.provisionNew();
      storage.failWrites = true;
      await expectLater(vault.confirmBackup(), throwsStateError);
      expect(await const SeedVault().status, WalletStatus.backupPending);
      expect(await vault.readMnemonicForBackup(), phrase);
      await expectLater(vault.readSeed(), throwsStateError);
      storage.failWrites = false;
      await vault.confirmBackup();
      expect(await vault.readSeed(), bip39.mnemonicToSeed(phrase));
    },
  );

  test(
    'failed creation does not provision a wallet or block a retry',
    () async {
      final storage = _FailingStorage()..failWrites = true;
      final vault = SeedVault(storage);
      await expectLater(vault.provisionNew(), throwsStateError);
      expect(await vault.status, WalletStatus.empty);
      storage.failWrites = false;
      final phrase = await vault.provisionNew();
      expect(await vault.readMnemonicForBackup(), phrase);
    },
  );

  test(
    'unreadable wallet data neither falls back nor gets overwritten',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        _legacyKey: _mnemonic,
        _walletKey: '{"mnemonic":"abandon',
      });
      await expectLater(
        _vault.status,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            isNot(contains('abandon')),
          ),
        ),
      );
      await expectLater(_vault.provisionNew(), throwsStateError);
      await expectLater(_vault.importMnemonic(_mnemonic), throwsStateError);
    },
  );

  testWidgets(
    'Back and app recreation resume backup before enabling wallet use',
    (tester) async {
      await _restart(tester);
      await _tap(tester, 'Set up testnet wallet');
      await _tap(tester, 'Create new wallet');
      final phrase = await _vault.readMnemonicForBackup();
      expect(find.text(phrase), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Backup not confirmed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Scan Vizor request'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Connect to Vizor Desktop'), findsNothing);
      await _tap(tester, 'Finish wallet backup');
      expect(find.text(phrase), findsOneWidget);
      await _restart(tester);
      await _tap(tester, 'Finish wallet backup');
      expect(find.text(phrase), findsOneWidget);
      expect(find.text('Create new wallet'), findsNothing);
      expect(find.text('Import existing wallet'), findsNothing);
      await _tap(tester, 'I saved the backup');
      expect(find.text('Testnet key ready'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Scan Vizor request'),
            )
            .onPressed,
        isNotNull,
      );
      await _restart(tester);
      expect(find.text('Testnet key ready'), findsOneWidget);
      expect(await _vault.readMnemonicForBackup(), phrase);
    },
  );

  testWidgets('legacy wallets resume backup through the UI', (tester) async {
    FlutterSecureStorage.setMockInitialValues({_legacyKey: _mnemonic});
    await _restart(tester);
    await _tap(tester, 'Finish wallet backup');
    expect(find.text(_mnemonic), findsOneWidget);
    await _tap(tester, 'I saved the backup');
    expect(find.text('Testnet key ready'), findsOneWidget);
    expect(await _vault.readSeed(), bip39.mnemonicToSeed(_mnemonic));
  });

  testWidgets('storage errors keep wallet actions disabled', (tester) async {
    FlutterSecureStorage.setMockInitialValues({_walletKey: 'broken'});
    await _restart(tester);
    await tester.scrollUntilVisible(
      find.text('Wallet unavailable'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Wallet unavailable'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Retry wallet access'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Retry wallet access'), findsOneWidget);
    expect(find.text('Set up testnet wallet'), findsNothing);
    expect(find.text('Finish wallet backup'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Scan Vizor request'),
          )
          .onPressed,
      isNull,
    );
  });
}
