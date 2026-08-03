import 'dart:math' as math;

import 'package:zxcvbn/zxcvbn.dart';

typedef PasswordRandomInt = int Function(int max);

class PasswordGeneratorOptions {
  const PasswordGeneratorOptions({
    this.length = 20,
    this.useLowercase = true,
    this.useUppercase = true,
    this.useNumbers = true,
    this.useSymbols = true,
    this.excludeAmbiguous = true,
  });

  final int length;
  final bool useLowercase;
  final bool useUppercase;
  final bool useNumbers;
  final bool useSymbols;
  final bool excludeAmbiguous;

  int get enabledPoolCount => [
    useLowercase,
    useUppercase,
    useNumbers,
    useSymbols,
  ].where((enabled) => enabled).length;

  PasswordGeneratorOptions copyWith({
    int? length,
    bool? useLowercase,
    bool? useUppercase,
    bool? useNumbers,
    bool? useSymbols,
    bool? excludeAmbiguous,
  }) {
    return PasswordGeneratorOptions(
      length: length ?? this.length,
      useLowercase: useLowercase ?? this.useLowercase,
      useUppercase: useUppercase ?? this.useUppercase,
      useNumbers: useNumbers ?? this.useNumbers,
      useSymbols: useSymbols ?? this.useSymbols,
      excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
    );
  }
}

String generatePassword(
  PasswordGeneratorOptions options, {
  PasswordRandomInt? randomInt,
}) {
  if (options.length < 6 || options.length > 64) {
    throw const FormatException('Password length must be between 6 and 64');
  }

  final pools =
      <String>[
        if (options.useLowercase) 'abcdefghijklmnopqrstuvwxyz',
        if (options.useUppercase) 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        if (options.useNumbers) '0123456789',
        if (options.useSymbols) r'!@#$%^&*()-_=+[]{};:,.?',
      ].map((pool) {
        if (!options.excludeAmbiguous) return pool;
        return pool.split('').where((char) => !'Il1O0o'.contains(char)).join();
      }).toList();

  if (pools.isEmpty) {
    throw const FormatException('At least one character set is required');
  }
  if (options.length < pools.length) {
    throw const FormatException('Password is too short for selected sets');
  }

  final secureRandom = math.Random.secure();
  int nextInt(int max) {
    final value = randomInt?.call(max) ?? secureRandom.nextInt(max);
    if (value < 0 || value >= max) {
      throw RangeError.range(value, 0, max - 1, 'random value');
    }
    return value;
  }

  final combined = pools.join();
  final characters = <String>[
    for (final pool in pools) pool[nextInt(pool.length)],
  ];
  while (characters.length < options.length) {
    characters.add(combined[nextInt(combined.length)]);
  }
  for (var index = characters.length - 1; index > 0; index--) {
    final swapIndex = nextInt(index + 1);
    final value = characters[index];
    characters[index] = characters[swapIndex];
    characters[swapIndex] = value;
  }
  return characters.join();
}

class PasswordStrength {
  const PasswordStrength(this.score);

  final int score;

  bool get isWeak => score <= 1;

  String get label => switch (score) {
    0 => '很弱',
    1 => '较弱',
    2 => '一般',
    3 => '较强',
    _ => '很强',
  };
}

final _strengthEstimator = Zxcvbn();

PasswordStrength evaluatePasswordStrength(
  String password, {
  List<String> userInputs = const [],
}) {
  if (password.isEmpty) return const PasswordStrength(0);
  final evaluatedPassword = password.length > 100
      ? password.substring(0, 100)
      : password;
  final inputs = userInputs
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .map((value) => value.length > 100 ? value.substring(0, 100) : value)
      .toList();
  final result = _strengthEstimator.evaluate(
    evaluatedPassword,
    userInputs: inputs,
  );
  final score = math.max(0, math.min(4, (result.score ?? 0).round()));
  return PasswordStrength(score);
}
