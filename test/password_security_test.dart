import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/security/password_audit.dart';
import 'package:account_book/security/password_security.dart';

void main() {
  test('密码生成器覆盖全部启用字符集并排除易混淆字符', () {
    var randomValue = 0;
    final password = generatePassword(
      const PasswordGeneratorOptions(length: 24),
      randomInt: (max) => randomValue++ % max,
    );

    expect(password, hasLength(24));
    expect(password, matches(RegExp('[a-z]')));
    expect(password, matches(RegExp('[A-Z]')));
    expect(password, matches(RegExp('[0-9]')));
    expect(password, matches(RegExp(r'[!@#$%^&*()\-_+=\[\]{};:,.?]')));
    expect(password, isNot(matches(RegExp('[Il1O0o]'))));
  });

  test('密码生成器拒绝无字符集和超出范围的长度', () {
    expect(
      () => generatePassword(
        const PasswordGeneratorOptions(
          useLowercase: false,
          useUppercase: false,
          useNumbers: false,
          useSymbols: false,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => generatePassword(const PasswordGeneratorOptions(length: 5)),
      throwsFormatException,
    );
  });

  test('密码生成器允许从 6 位开始生成', () {
    final password = generatePassword(
      const PasswordGeneratorOptions(length: 6),
      randomInt: (_) => 0,
    );

    expect(password, hasLength(6));
  });

  test('zxcvbn 对随机长密码的评分高于常见密码', () {
    final weak = evaluatePasswordStrength('password123');
    final strong = evaluatePasswordStrength(r'V7#pL2@qR9!mX4$kW8');

    expect(weak.isWeak, isTrue);
    expect(strong.score, greaterThan(weak.score));
    expect(strong.score, greaterThanOrEqualTo(3));
  });

  test('安全检查识别重复、弱、长期未更新和缺少保护的账号', () {
    final now = DateTime(2026, 8, 3);
    final old = now.subtract(const Duration(days: 400));
    const reusedPassword = r'S7!uQ2#xK9@rT4$z';
    final result = analyzePasswordAudit(
      PasswordAuditRequest(
        nowMs: now.millisecondsSinceEpoch,
        entries: [
          PasswordAuditEntry(
            title: '银行',
            username: 'alice',
            password: reusedPassword,
            hasTotp: false,
            updatedAt: now.millisecondsSinceEpoch,
          ),
          PasswordAuditEntry(
            title: '邮箱',
            username: 'alice@example.com',
            password: reusedPassword,
            hasTotp: true,
            updatedAt: now.millisecondsSinceEpoch,
          ),
          PasswordAuditEntry(
            title: '论坛',
            username: 'alice',
            password: 'password123',
            hasTotp: false,
            updatedAt: old.millisecondsSinceEpoch,
          ),
          PasswordAuditEntry(
            title: '验证器',
            username: 'alice',
            password: '',
            hasTotp: true,
            updatedAt: now.millisecondsSinceEpoch,
          ),
          PasswordAuditEntry(
            title: '损坏条目',
            username: '',
            password: '',
            hasTotp: false,
            updatedAt: now.millisecondsSinceEpoch,
          ),
        ],
      ),
    );

    expect(result.reusedAccounts, [0, 1]);
    expect(result.weakAccounts, contains(2));
    expect(result.staleAccounts, [2]);
    expect(result.unprotectedAccounts, [4]);
    expect(result.withoutTotpAccounts, [0, 2]);
    expect(result.attentionCount, 4);
  });

  test('安全检查请求和结果可在后台 isolate 间传输', () async {
    final result = await compute(
      analyzePasswordAudit,
      const PasswordAuditRequest(
        nowMs: 1,
        entries: [
          PasswordAuditEntry(
            title: '测试',
            username: 'user',
            password: 'password123',
            hasTotp: false,
            updatedAt: 1,
          ),
        ],
      ),
    );

    expect(result.totalAccounts, 1);
    expect(result.weakAccounts, [0]);
  });
}
