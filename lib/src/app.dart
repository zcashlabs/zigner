import 'package:airgapped_zcash_signer/src/security/vault_gate.dart';
import 'package:airgapped_zcash_signer/src/theme/signer_theme.dart';
import 'package:flutter/material.dart';

class SignerApp extends StatelessWidget {
  const SignerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zigner',
      builder: (context, child) =>
          PrivacyShield(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: SignerColors.mint,
          brightness: Brightness.dark,
          surface: SignerColors.surface,
        ),
        scaffoldBackgroundColor: SignerColors.background,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: SignerColors.surface,
          contentPadding: const EdgeInsets.all(18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: SignerColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: SignerColors.border),
          ),
        ),
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: SignerColors.text,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        cardTheme: CardThemeData(
          color: SignerColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: SignerColors.border),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: SignerColors.mint,
            foregroundColor: SignerColors.background,
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: SignerColors.text,
            minimumSize: const Size.fromHeight(56),
            side: const BorderSide(color: SignerColors.border),
            backgroundColor: SignerColors.surface,
            textStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textTheme: const TextTheme(
          displaySmall: TextStyle(
            color: SignerColors.text,
            fontFamily: 'Manrope',
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            height: 1.15,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Manrope',
            color: SignerColors.text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Manrope',
            color: SignerColors.text,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(color: SignerColors.textMuted, height: 1.5),
          bodyMedium: TextStyle(color: SignerColors.textMuted, height: 1.4),
        ),
        useMaterial3: true,
      ),
      home: const VaultGate(),
    );
  }
}
