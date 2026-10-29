String formatZec(BigInt zats) {
  final divisor = BigInt.from(100000000);
  final whole = zats ~/ divisor;
  final remainder = (zats % divisor).abs();
  final fraction = remainder
      .toString()
      .padLeft(8, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole ZEC' : '$whole.$fraction ZEC';
}
