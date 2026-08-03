import 'package:otp/otp.dart' as otp;

enum TotpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const TotpAlgorithm(this.wireName);

  final String wireName;

  static TotpAlgorithm parse(String value) {
    final normalized = value.trim().toUpperCase();
    return TotpAlgorithm.values.firstWhere(
      (algorithm) => algorithm.wireName == normalized,
      orElse: () => throw const FormatException('Unsupported TOTP algorithm'),
    );
  }

  otp.Algorithm get otpValue => switch (this) {
    TotpAlgorithm.sha1 => otp.Algorithm.SHA1,
    TotpAlgorithm.sha256 => otp.Algorithm.SHA256,
    TotpAlgorithm.sha512 => otp.Algorithm.SHA512,
  };
}

class TotpConfig {
  TotpConfig._({
    required this.secret,
    required this.issuer,
    required this.accountName,
    required this.algorithm,
    required this.digits,
    required this.period,
  });

  factory TotpConfig({
    required String secret,
    String issuer = '',
    String accountName = '',
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) {
    if (digits != 6 && digits != 8) {
      throw const FormatException('TOTP digits must be 6 or 8');
    }
    if (period < 15 || period > 120) {
      throw const FormatException('TOTP period is out of range');
    }
    final normalizedIssuer = issuer.trim();
    final normalizedAccountName = accountName.trim();
    if (normalizedIssuer.length > 512 || normalizedAccountName.length > 512) {
      throw const FormatException('TOTP label is too long');
    }
    final normalizedSecret = normalizeSecret(secret);
    try {
      otp.OTP.generateTOTPCodeString(
        normalizedSecret,
        0,
        length: digits,
        interval: period,
        algorithm: algorithm.otpValue,
        isGoogle: true,
      );
    } on FormatException {
      throw const FormatException('Invalid Base32 TOTP secret');
    }
    return TotpConfig._(
      secret: normalizedSecret,
      issuer: normalizedIssuer,
      accountName: normalizedAccountName,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
  }

  factory TotpConfig.fromInput(
    String input, {
    String issuer = '',
    String accountName = '',
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) {
    final value = input.trim();
    if (value.toLowerCase().startsWith('otpauth:')) {
      return TotpConfig.fromUri(value);
    }
    return TotpConfig(
      secret: value,
      issuer: issuer,
      accountName: accountName,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
  }

  factory TotpConfig.fromUri(String source) {
    final uri = Uri.tryParse(source.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'otpauth' ||
        uri.host.toLowerCase() != 'totp') {
      throw const FormatException('Unsupported otpauth URI');
    }

    final query = <String, String>{};
    for (final entry in uri.queryParametersAll.entries) {
      final key = entry.key.toLowerCase();
      if (entry.value.length != 1 || query.containsKey(key)) {
        throw const FormatException('Duplicate otpauth parameter');
      }
      query[key] = entry.value.single;
    }
    final secret = query['secret'];
    if (secret == null || secret.trim().isEmpty) {
      throw const FormatException('Missing TOTP secret');
    }

    final label = uri.pathSegments.join('/').trim();
    if (label.isEmpty) {
      throw const FormatException('Missing TOTP label');
    }
    final separator = label.indexOf(':');
    final labelIssuer = separator < 0 ? '' : label.substring(0, separator);
    final accountName = separator < 0 ? label : label.substring(separator + 1);
    final issuer = query['issuer'] ?? labelIssuer;
    if (accountName.trim().isEmpty) {
      throw const FormatException('Missing TOTP account name');
    }

    final rawDigits = query['digits'];
    final rawPeriod = query['period'];
    return TotpConfig(
      secret: secret,
      issuer: issuer,
      accountName: accountName,
      algorithm: TotpAlgorithm.parse(query['algorithm'] ?? 'SHA1'),
      digits: rawDigits == null ? 6 : int.tryParse(rawDigits) ?? -1,
      period: rawPeriod == null ? 30 : int.tryParse(rawPeriod) ?? -1,
    );
  }

  factory TotpConfig.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid TOTP configuration');
    }
    final secret = raw['secret'];
    final issuer = raw['issuer'];
    final accountName = raw['accountName'];
    final algorithm = raw['algorithm'];
    final digits = raw['digits'];
    final period = raw['period'];
    if (secret is! String ||
        issuer is! String ||
        accountName is! String ||
        algorithm is! String ||
        digits is! int ||
        period is! int) {
      throw const FormatException('Invalid TOTP configuration');
    }
    return TotpConfig(
      secret: secret,
      issuer: issuer,
      accountName: accountName,
      algorithm: TotpAlgorithm.parse(algorithm),
      digits: digits,
      period: period,
    );
  }

  String secret;
  String issuer;
  String accountName;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;

  String codeAt(DateTime time) {
    return otp.OTP.generateTOTPCodeString(
      secret,
      time.millisecondsSinceEpoch,
      length: digits,
      interval: period,
      algorithm: algorithm.otpValue,
      isGoogle: true,
    );
  }

  int remainingSeconds(DateTime time) {
    final elapsed = (time.millisecondsSinceEpoch ~/ 1000) % period;
    return period - elapsed;
  }

  String get displayName {
    if (issuer.isEmpty) return accountName;
    if (accountName.isEmpty) return issuer;
    return '$issuer · $accountName';
  }

  Map<String, Object> toJson() {
    return {
      'secret': secret,
      'issuer': issuer,
      'accountName': accountName,
      'algorithm': algorithm.wireName,
      'digits': digits,
      'period': period,
    };
  }

  TotpConfig copy() {
    return TotpConfig(
      secret: secret,
      issuer: issuer,
      accountName: accountName,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
  }

  void wipe() {
    secret = '';
    issuer = '';
    accountName = '';
  }

  static String normalizeSecret(String source) {
    final compact = source.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z2-7]+=*$').hasMatch(compact)) {
      throw const FormatException('Invalid Base32 TOTP secret');
    }
    final normalized = compact.replaceFirst(RegExp(r'=+$'), '');
    final remainder = normalized.length % 8;
    if (normalized.length < 16 ||
        normalized.length > 1024 ||
        remainder == 1 ||
        remainder == 3 ||
        remainder == 6) {
      throw const FormatException('Invalid Base32 TOTP secret');
    }
    return normalized;
  }
}

String formatTotpCode(String code) {
  final split = code.length ~/ 2;
  return '${code.substring(0, split)} ${code.substring(split)}';
}
