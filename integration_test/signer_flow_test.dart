import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:airgapped_zcash_signer/src/app.dart';
import 'package:airgapped_zcash_signer/src/rust/frb_generated.dart';
import 'package:airgapped_zcash_signer/src/screens/qr_scanner_screen.dart';
import 'package:airgapped_zcash_signer/src/screens/review_screen.dart';
import 'package:airgapped_zcash_signer/src/screens/signature_screen.dart';
import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:airgapped_zcash_signer/src/util/zec_format.dart';
import 'package:airgapped_zcash_signer/src/widgets/animated_ur_qr.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'signer_flow_fixture.dart';

final _fixture = jsonDecode(signerFlowFixtureJson) as Map<String, dynamic>;
final _expected = _fixture['expected'] as Map<String, dynamic>;
const _vault = SeedVault();

List<String> _parts(String field) =>
    (_fixture[field] as List<dynamic>).cast<String>();

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

// QR timers prevent pumpAndSettle.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 350));
      return;
    }
  }
  fail('Timed out waiting for $finder');
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 30,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _start(WidgetTester tester) async {
  await tester.pumpWidget(const SignerApp());
  await _waitFor(tester, find.text('Wallet not set up'));
  expect(find.text('SECURE SESSION  ·  TESTNET'), findsOneWidget);
  await _tap(tester, find.text('Set up testnet wallet'));
  await _waitFor(tester, find.text('Create new wallet'));
}

Future<void> _scanFixture(WidgetTester tester) async {
  await _tap(tester, find.text('Scan Vizor request'));
  await _waitFor(tester, find.byType(QrScannerScreen));
  await _waitFor(tester, find.byType(Texture));
  final onDetect = tester
      .widget<MobileScanner>(find.byType(MobileScanner))
      .onDetect!;

  void deliver(String part) => onDetect(
    BarcodeCapture(
      barcodes: [Barcode(rawValue: part, format: BarcodeFormat.qrCode)],
    ),
  );

  deliver('ur:bytes/abcd');
  await tester.pump();
  expect(find.textContaining('Expected a zcash-sign-batch QR'), findsOneWidget);

  final parts = _parts('requestUrParts').reversed.toList();
  expect(parts.length, greaterThan(1));
  deliver(parts.first);
  deliver(parts.first); // Exercise repeated frames.
  for (final part in parts.skip(1)) {
    deliver(part);
    await tester.pump(const Duration(milliseconds: 10));
  }
  await _waitFor(tester, find.byType(ReviewScreen));
  final review = tester.widget<ReviewScreen>(find.byType(ReviewScreen)).review;
  expect(review.requestIdHex, _fixture['requestIdHex']);
  expect(review.requestDigest, _expected['requestDigest']);
  for (final text in [
    '${_expected['transactionCount']} transactions',
    'ORCHARD ${_expected['orchardSpendCount']}',
    'IRONWOOD ${_expected['ironwoodSpendCount']}',
    formatZec(BigInt.parse('${_expected['visibleOutputTotalZat']}')),
    ...(_expected['outputs'] as List<dynamic>).cast<String>(),
    _fixture['requestIdHex'] as String,
    _expected['requestDigest'] as String,
  ]) {
    await _show(tester, find.text(text));
    expect(find.text(text).hitTestable(), findsOneWidget);
  }
}

Future<void> _checkQrCycle(WidgetTester tester, List<String> parts) async {
  final counter = find.textContaining(RegExp(r'^QR \d+ of \d+$'));
  int frame() =>
      int.parse(tester.widget<Text>(counter).data!.split(' ')[1]) - 1;
  final first = frame();
  final seen = <int>{};
  for (var tick = 0; tick < parts.length * 15; tick++) {
    final index = frame();
    expect(find.text('QR ${index + 1} of ${parts.length}'), findsOneWidget);
    if (seen.add(index)) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(QrImageView),
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter is QrPainter,
          ),
        ),
      );
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      final actual = await (paint.painter! as QrPainter).toImageData(
        160,
        format: ui.ImageByteFormat.rawRgba,
      );
      final expected = await QrPainter(
        data: parts[index],
        version: qr.version,
        errorCorrectionLevel: qr.errorCorrectionLevel,
        gapless: qr.gapless,
        eyeStyle: qr.eyeStyle,
        dataModuleStyle: qr.dataModuleStyle,
      ).toImageData(160, format: ui.ImageByteFormat.rawRgba);
      expect(actual!.buffer.asUint8List(), expected!.buffer.asUint8List());
    } else if (seen.length == parts.length && index == first) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('QR animation did not display every frame and wrap');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!Platform.isAndroid ||
        (await Process.run('/system/bin/getprop', [
              'ro.kernel.qemu',
            ])).stdout.toString().trim() !=
            '1') {
      throw StateError(
        'These tests clear wallet data; use a disposable Android emulator.',
      );
    }
    await RustLib.init();
  });
  setUp(() async {
    binding.reportData = null;
    await _vault.delete();
  });
  tearDown(_vault.delete);

  testWidgets('create a testnet wallet and acknowledge its backup', (
    tester,
  ) async {
    await _start(tester);
    await _tap(tester, find.text('Create new wallet'));
    await _waitFor(tester, find.text('I saved the backup'));
    final phrase = await _vault.readMnemonicForBackup();
    expect(bip39.validateMnemonic(phrase), isTrue);
    expect(phrase.split(' '), hasLength(24));
    expect(find.text(phrase), findsOneWidget);
    expect(await _vault.isProvisioned, isFalse);
    await expectLater(_vault.readSeed(), throwsStateError);
    await tester.pageBack();
    await _waitFor(tester, find.text('Backup not confirmed'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Scan Vizor request'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Connect to Vizor Desktop'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(const SignerApp());
    await _waitFor(tester, find.text('Finish wallet backup'));
    await _tap(tester, find.text('Finish wallet backup'));
    await _waitFor(tester, find.text('I saved the backup'));
    expect(find.text(phrase), findsOneWidget);
    expect(await _vault.readMnemonicForBackup(), phrase);
    await _tap(tester, find.text('I saved the backup'));
    await _waitFor(tester, find.text('Testnet key ready'));
    expect(await _vault.readMnemonicForBackup(), phrase);
  });

  testWidgets('import, pair, scan, reject, approve, sign, and return to home', (
    tester,
  ) async {
    await _start(tester);
    await tester.enterText(
      find.byType(TextField),
      _fixture['mnemonic'] as String,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 350));
    await _tap(tester, find.text('Import existing wallet'));
    await _waitFor(tester, find.text('Testnet key ready'));
    expect(_hex(await _vault.readSeed()), _fixture['seedHex']);

    await _tap(tester, find.text('Connect to Vizor Desktop'));
    await _waitFor(tester, find.byType(AnimatedUrQr));
    final accountParts = List<String>.of(
      tester.widget<AnimatedUrQr>(find.byType(AnimatedUrQr)).parts,
    );
    expect(accountParts, _parts('accountUrParts'));
    expect(accountParts, everyElement(startsWith('UR:ZCASH-ACCOUNTS/')));
    await _checkQrCycle(tester, accountParts);
    await tester.pageBack();
    await _waitFor(tester, find.text('Testnet key ready'));

    await _scanFixture(tester);
    final approve = find.widgetWithText(FilledButton, 'Approve and sign PCZT');
    await tester.scrollUntilVisible(
      approve,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<FilledButton>(approve).onPressed, isNull);
    await tester.pageBack();
    await _waitFor(tester, find.text('Testnet key ready'));
    expect(find.byType(SignatureScreen), findsNothing);
    await _scanFixture(tester);
    await _tap(tester, find.byType(CheckboxListTile));
    await _tap(tester, approve);
    await _waitFor(tester, find.byType(SignatureScreen));

    final signed = tester
        .widget<SignatureScreen>(find.byType(SignatureScreen))
        .signature;
    expect(signed.requestIdHex, _fixture['requestIdHex']);
    expect(signed.signatureCount, _expected['signatureCount']);
    expect(signed.urParts, isNotEmpty);
    expect(
      signed.urParts,
      everyElement(startsWith('UR:ZCASH-BATCH-SIG-RESULT/')),
    );
    expect(
      tester.widget<AnimatedUrQr>(find.byType(AnimatedUrQr)).parts,
      signed.urParts,
    );
    await _checkQrCycle(tester, signed.urParts);

    binding.reportData = {
      'fixtureSchemaVersion': _fixture['schemaVersion'],
      'requestIdHex': signed.requestIdHex,
      'accountUrParts': accountParts,
      'signedResponseUrParts': signed.urParts,
    };
    await _tap(tester, find.text('Finish session'));
    await _waitFor(tester, find.text('Testnet key ready'));
    expect(_hex(await _vault.readSeed()), _fixture['seedHex']);
  });
}
