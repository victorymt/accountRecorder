import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/totp/totp_service.dart';

void main() {
  test('TOTP 符合 RFC 6238 SHA1 标准向量', () {
    final config = TotpConfig(
      secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
      algorithm: TotpAlgorithm.sha1,
      digits: 8,
      period: 30,
    );

    expect(
      config.codeAt(DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true)),
      '94287082',
    );
    expect(
      config.codeAt(
        DateTime.fromMillisecondsSinceEpoch(1111111109000, isUtc: true),
      ),
      '07081804',
    );
  });

  test('完整解析 otpauth URI 参数与编码标签', () {
    final config = TotpConfig.fromUri(
      'otpauth://totp/Example:alice%40example.com'
      '?secret=jbsw-y3dp-ehpk-3pxp'
      '&issuer=Example&algorithm=SHA256&digits=8&period=60',
    );

    expect(config.secret, 'JBSWY3DPEHPK3PXP');
    expect(config.issuer, 'Example');
    expect(config.accountName, 'alice@example.com');
    expect(config.algorithm, TotpAlgorithm.sha256);
    expect(config.digits, 8);
    expect(config.period, 60);
    expect(config.displayName, 'Example · alice@example.com');
  });

  test('手动密钥规范化并完整往返 JSON', () {
    final config = TotpConfig.fromInput(
      'jbsw y3dp ehpk 3pxp',
      issuer: '邮箱',
      accountName: 'user@example.com',
    );
    final restored = TotpConfig.fromJson(config.toJson());

    expect(restored.secret, 'JBSWY3DPEHPK3PXP');
    expect(restored.issuer, '邮箱');
    expect(restored.accountName, 'user@example.com');
    expect(restored.algorithm, TotpAlgorithm.sha1);
    expect(restored.digits, 6);
    expect(restored.period, 30);
  });

  test('拒绝 HOTP、重复参数和无效密钥', () {
    expect(
      () => TotpConfig.fromUri(
        'otpauth://hotp/Example:user?secret=JBSWY3DPEHPK3PXP&counter=1',
      ),
      throwsFormatException,
    );
    expect(
      () => TotpConfig.fromUri(
        'otpauth://totp/Example:user'
        '?secret=JBSWY3DPEHPK3PXP&secret=AAAAAAAAAAAAAAAA',
      ),
      throwsFormatException,
    );
    expect(() => TotpConfig(secret: 'not-base32'), throwsFormatException);
  });

  test('倒计时与分组显示按配置周期计算', () {
    final config = TotpConfig(secret: 'JBSWY3DPEHPK3PXP', period: 30);
    expect(
      config.remainingSeconds(
        DateTime.fromMillisecondsSinceEpoch(31000, isUtc: true),
      ),
      29,
    );
    expect(formatTotpCode('123456'), '123 456');
    expect(formatTotpCode('12345678'), '1234 5678');
  });

  test('主页刷新等待到最近的 TOTP 周期边界', () {
    final thirtySeconds = TotpConfig(secret: 'JBSWY3DPEHPK3PXP', period: 30);
    final sixtySeconds = TotpConfig(secret: 'JBSWY3DPEHPK3PXP', period: 60);

    expect(
      timeUntilNextTotpChange([
        thirtySeconds,
        sixtySeconds,
      ], DateTime.fromMillisecondsSinceEpoch(29000)),
      const Duration(seconds: 1),
    );
    expect(
      timeUntilNextTotpChange([
        thirtySeconds,
      ], DateTime.fromMillisecondsSinceEpoch(30000)),
      const Duration(seconds: 30),
    );
    expect(timeUntilNextTotpChange(const [], DateTime.now()), Duration.zero);
  });
}
