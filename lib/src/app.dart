import 'package:airgapped_zcash_signer/src/screens/home_screen.dart';
import 'package:airgapped_zcash_signer/src/theme/signer_theme.dart';
import 'package:flutter/material.dart';

class SignerApp extends StatelessWidget {
  const SignerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zcash Testnet Airgap Signer',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: SignerColors.gold,
          brightness: Brightness.dark,
          surface: SignerColors.surface,
        ),
        scaffoldBackgroundColor: SignerColors.background,
        fontFamily: 'sans-serif',
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
            backgroundColor: SignerColors.gold,
            foregroundColor: SignerColors.background,
            minimumSize: const Size.fromHeight(58),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: SignerColors.text,
            minimumSize: const Size.fromHeight(58),
            side: const BorderSide(color: SignerColors.border),
            backgroundColor: SignerColors.surface,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        textTheme: const TextTheme(
          displaySmall: TextStyle(
            color: SignerColors.text,
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.8,
            height: 1.05,
          ),
          headlineSmall: TextStyle(
            color: SignerColors.text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          titleMedium: TextStyle(
            color: SignerColors.text,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(color: SignerColors.textMuted, height: 1.5),
          bodyMedium: TextStyle(color: SignerColors.textMuted, height: 1.4),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
