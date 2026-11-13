import 'dart:async';

import 'package:airgapped_zcash_signer/src/screens/provision_screen.dart';
import 'package:airgapped_zcash_signer/src/screens/settings_screen.dart';
import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:airgapped_zcash_signer/src/security/vault_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ready = VaultStatus(
    hasSigner: false,
    ready: true,
    protection: 'strongbox',
  );
  const publicPhrase =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  final questions = [
    for (final i in [0, 11, 23])
      {
        'index': i,
        'choices': ['word${i + 1}', 'wrong', 'other', 'paper', 'check', 'test'],
      },
  ];
  late List<MethodCall> calls;
  late bool completed, cancelAuthentication, rejectImport;
  late int verified;
  Completer<void>? importGate;
  Completer<void>? authGate;
  setUp(() {
    calls = [];
    completed = false;
    cancelAuthentication = false;
    rejectImport = false;
    verified = 0;
    importGate = null;
    authGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SeedVault.channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'status':
              return {
                'hasSigner': true,
                'ready': true,
                'protection': 'strongbox',
              };
            case 'generate':
              return {
                'words': List.generate(24, (i) => 'word${i + 1}'),
                'challenge': [0, 11, 23],
                'questions': questions,
              };
            case 'inspectPhrase':
              final phrase = call.arguments['mnemonic'] as String;
              return {
                'count': phrase.trim().split(RegExp(r'\s+')).length,
                'valid': phrase == publicPhrase,
                'suggestions': <String>[],
              };
            case 'checkBackupWord':
              expect(call.arguments['question'], verified);
              final correct =
                  call.arguments['word'] ==
                  ['word1', 'word12', 'word24'][verified];
              if (correct) verified++;
              return {'correct': correct, 'complete': verified == 3};
            case 'restartBackupCheck':
              verified = 0;
              return null;
            case 'prepareImport':
              await importGate?.future;
              if (rejectImport) {
                throw PlatformException(
                  code: 'VAULT_ERROR',
                  message: 'Recovery phrase checksum is invalid.',
                );
              }
              return null;
            case 'save':
            case 'unlock':
            case 'erase':
              await authGate?.future;
              if (cancelAuthentication) {
                throw PlatformException(
                  code: 'AUTH_CANCELLED',
                  message: 'Authentication cancelled.',
                );
              }
              return null;
            default:
              return null;
          }
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SeedVault.channel, null),
  );
  Future<void> show(WidgetTester tester, {VaultStatus status = ready}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ProvisionScreen(
          status: status,
          onProvisioned: () => completed = true,
          onRetry: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tap(tester, 'Get started');
    await tap(tester, 'Continue');
  }

  Future<void> create(WidgetTester tester) async {
    await choose(tester);
    await tap(tester, 'Create a new signer');
    await tap(tester, 'I’m ready, show my words');
  }

  Future<void> enterImport(WidgetTester tester) async {
    await choose(tester);
    await tap(tester, 'I have a recovery phrase');
    await tester.enterText(find.byType(TextField), publicPhrase);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tap(tester, 'Continue');
  }

  void background(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void vaultTest(String name, WidgetTesterCallback test) {
    testWidgets(name, (tester) async {
      try {
        await test(tester);
      } finally {
        if (importGate != null && !importGate!.isCompleted) {
          importGate!.complete();
        }
        // Drain route-disposal cleanup within this test's platform-channel zone.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  vaultTest(
    'create hides words and requires paper, three native answers, then authentication',
    (tester) async {
      await show(tester);
      await create(tester);
      expect(find.text('word1'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Check my backup'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'Reveal recovery words');
      expect(find.text('word1'), findsOneWidget);
      await tap(tester, 'I wrote down all 24 words in order.');
      await tap(tester, 'Check my backup');
      await tap(tester, 'wrong');
      expect(verified, 0);
      expect(calls.any((c) => c.method == 'save'), false);
      for (final word in ['word1', 'word12', 'word24']) {
        await tap(tester, word);
      }
      expect(calls.any((c) => c.method == 'save'), false);
      await tap(tester, 'Continue');
      await tap(tester, 'Unlock to protect');
      expect(calls.where((c) => c.method == 'save'), hasLength(1));
      expect(completed, false); // Ready screen precedes home.
      await tap(tester, 'I’ll do this later');
      expect(completed, true);
    },
  );
  vaultTest(
    'debug skip bypasses the quiz but still requires Android protection',
    (tester) async {
      await show(tester);
      await create(tester);
      await tap(tester, 'Reveal recovery words');
      await tap(tester, 'I wrote down all 24 words in order.');
      await tap(tester, 'Check my backup');
      await tap(tester, 'Skip backup check · debug only');
      expect(
        calls.where((c) => c.method == 'skipBackupCheckForDebug'),
        hasLength(1),
      );
      expect(calls.any((c) => c.method == 'checkBackupWord'), false);
      expect(calls.any((c) => c.method == 'save'), false);
      expect(find.text('Your backup\nlooks right.'), findsNothing);
      await tap(tester, 'Unlock to protect');
      expect(calls.where((c) => c.method == 'save'), hasLength(1));
      expect(find.text('Your signer\nis ready.'), findsOneWidget);
    },
  );

  vaultTest('setup remains scrollable with large text on a smaller screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester);
    tester.view.physicalSize = const Size(390, 700);
    await tester.pumpAndSettle();
    await create(tester);
    expect(find.text('Reveal recovery words'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  vaultTest(
    'import checks checksum, disables keyboard learning, confirms optional passphrase',
    (tester) async {
      await show(tester);
      await choose(tester);
      await tap(tester, 'I have a recovery phrase');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enableIMEPersonalizedLearning, false);
      expect(field.autocorrect, false);
      expect(field.enableInteractiveSelection, false);
      await tester.enterText(find.byType(TextField), 'invalid test phrase');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), publicPhrase);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tap(tester, 'Continue');
      await tap(tester, 'I used an extra passphrase');
      await tester.enterText(find.byType(TextField).at(0), 'public-pass');
      await tester.enterText(find.byType(TextField).at(1), 'mismatch');
      await tap(tester, 'Continue with passphrase');
      expect(calls.any((c) => c.method == 'prepareImport'), false);
      await tester.enterText(find.byType(TextField).at(1), 'public-pass');
      await tap(tester, 'Continue with passphrase');
      expect(
        calls
            .lastWhere((c) => c.method == 'prepareImport')
            .arguments['passphrase'],
        'public-pass',
      );
      expect(field.controller!.text, isEmpty);
      expect(find.byType(TextField), findsNothing);
      await tap(tester, 'Unlock to protect');
      expect(find.text('Your signer\nis ready.'), findsOneWidget);
    },
  );
  vaultTest(
    'unavailable hardware blocks setup; legacy signer only offers upgrade',
    (tester) async {
      await show(
        tester,
        status: const VaultStatus(
          hasSigner: false,
          ready: false,
          protection: 'unavailable',
          error: 'Set a device PIN first.',
        ),
      );
      expect(find.text('Create a new signer'), findsNothing);
      expect(find.text('Set a device PIN first.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await show(
        tester,
        status: const VaultStatus(
          hasSigner: true,
          ready: true,
          protection: 'strongbox',
          hasLegacySigner: true,
        ),
      );
      expect(find.text('Upgrade signer protection'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
    },
  );
  vaultTest('background abandons recovery words and unsaved draft', (
    tester,
  ) async {
    await show(tester);
    await create(tester);
    await tap(tester, 'Reveal recovery words');
    background(tester);
    await tester.pumpAndSettle();
    expect(find.text('word1'), findsNothing);
    expect(calls.any((c) => c.method == 'discardDraft'), true);
    expect(calls.any((c) => c.method == 'save'), false);
  });
  vaultTest('authentication cancellation leaves protect screen retryable', (
    tester,
  ) async {
    await show(tester);
    await enterImport(tester);
    await tap(tester, 'Continue without passphrase');
    cancelAuthentication = true;
    await tap(tester, 'Unlock to protect');
    expect(find.text('Authentication cancelled.'), findsOneWidget);
    expect(completed, false);
    cancelAuthentication = false;
    await tap(tester, 'Unlock to protect');
    await tap(tester, 'I’ll do this later');
    expect(completed, true);
  });
  vaultTest('background during failed validation clears input before reuse', (
    tester,
  ) async {
    await show(tester);
    await enterImport(tester);
    importGate = Completer<void>();
    rejectImport = true;
    await tester.tap(find.text('Continue without passphrase'));
    await tester.pump();
    background(tester);
    importGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Create a new signer'), findsOneWidget);
    expect(completed, false);
    await tap(tester, 'I have a recovery phrase');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
  vaultTest(
    'privacy shield removes content from rendering and accessibility while inactive',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PrivacyShield(child: Text('sensitive test words')),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('sensitive test words'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('sensitive test words'), findsOneWidget);
    },
  );
  vaultTest(
    'erase needs paper acknowledgement, exact word, and native authentication',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: EraseSignerScreen(onErased: () => completed = true)),
      );
      final button = find.widgetWithText(FilledButton, 'Erase signer');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'erase');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tap(
        tester,
        'I have my recovery words and any extra passphrase backed up.',
      );
      cancelAuthentication = true;
      await tap(tester, 'Erase signer');
      expect(completed, false);
      cancelAuthentication = false;
      await tap(tester, 'Erase signer');
      expect(completed, true);
      expect(
        calls.lastWhere((c) => c.method == 'erase').arguments['confirmation'],
        'erase',
      );
    },
  );
  vaultTest('app opens locked and relocks on background without reading seed', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: VaultGate()));
    await tester.pumpAndSettle();
    expect(find.text('Unlock to open signer'), findsOneWidget);
    await tap(tester, 'Unlock to open signer');
    expect(find.text('All quiet.\nReady when you are.'), findsOneWidget);
    expect(calls.any((c) => c.method == 'readSeed'), false);
    background(tester);
    await tester.pumpAndSettle();
    expect(find.text('Unlock to open signer'), findsOneWidget);
  });
  vaultTest(
    'cancelled system authentication after background also locks the app session',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VaultGate()));
      await tester.pumpAndSettle();
      await tap(tester, 'Unlock to open signer');
      authGate = Completer<void>();
      cancelAuthentication = true;
      final cancelled = const SeedVault().unlock().catchError((Object _) {});
      await tester.pump();
      background(tester);
      await tester.pump();
      authGate!.complete();
      await cancelled;
      await tester.pumpAndSettle();
      expect(find.text('Unlock to open signer'), findsOneWidget);
    },
  );
}
