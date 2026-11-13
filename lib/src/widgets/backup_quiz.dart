import 'package:flutter/material.dart';

import '../security/seed_vault.dart';
import '../theme/signer_theme.dart';

/// The native vault validates each answer; Flutter cannot mark the backup complete.
class BackupQuiz extends StatefulWidget {
  const BackupQuiz({
    super.key,
    required this.questions,
    required this.onComplete,
  });
  final List<BackupQuestion> questions;
  final VoidCallback onComplete;
  @override
  State<BackupQuiz> createState() => _BackupQuizState();
}

class _BackupQuizState extends State<BackupQuiz> {
  int _question = 0;
  bool _busy = false;
  String? _message;
  Future<void> _answer(String word) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await const SeedVault().checkBackupWord(_question, word);
      if (!mounted) return;
      if (result.complete) {
        widget.onComplete();
      } else if (result.correct) {
        setState(() => _question++);
      } else {
        setState(
          () => _message = 'That word doesn’t match. Take another look at your paper backup.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = vaultErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.questions[_question];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: Icon(
                    i < _question ? Icons.check_rounded : Icons.circle_outlined,
                    size: 16,
                    color: i <= _question
                        ? SignerColors.mint
                        : SignerColors.textMuted,
                  ),
                  label: Text('${i + 1}'),
                  backgroundColor: SignerColors.surface,
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        SignerCard(
          child: Column(
            children: [
              Text(
                'QUESTION ${_question + 1} OF 3',
                style: const TextStyle(fontSize: 11, letterSpacing: 1.2),
              ),
              const SizedBox(height: 12),
              Text(
                'Which is word ${question.index + 1}?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final word in question.choices)
                      SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _answer(word),
                          child: Text(
                            word,
                            style: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 16),
          QuietNotice(_message!, warning: true),
        ],
      ],
    );
  }
}
