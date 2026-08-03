import 'password_security.dart';

class PasswordAuditEntry {
  const PasswordAuditEntry({
    required this.title,
    required this.username,
    required this.password,
    required this.hasTotp,
    required this.updatedAt,
  });

  final String title;
  final String username;
  final String password;
  final bool hasTotp;
  final int? updatedAt;
}

class PasswordAuditRequest {
  const PasswordAuditRequest({required this.entries, required this.nowMs});

  final List<PasswordAuditEntry> entries;
  final int nowMs;
}

class PasswordAuditResult {
  const PasswordAuditResult({
    required this.totalAccounts,
    required this.reusedAccounts,
    required this.weakAccounts,
    required this.staleAccounts,
    required this.unprotectedAccounts,
    required this.withoutTotpAccounts,
  });

  final int totalAccounts;
  final List<int> reusedAccounts;
  final List<int> weakAccounts;
  final List<int> staleAccounts;
  final List<int> unprotectedAccounts;
  final List<int> withoutTotpAccounts;

  int get attentionCount => {
    ...reusedAccounts,
    ...weakAccounts,
    ...staleAccounts,
    ...unprotectedAccounts,
  }.length;
}

PasswordAuditResult analyzePasswordAudit(PasswordAuditRequest request) {
  final passwordIndexes = <String, List<int>>{};
  final weakAccounts = <int>[];
  final staleAccounts = <int>[];
  final unprotectedAccounts = <int>[];
  final withoutTotpAccounts = <int>[];
  const staleAfter = Duration(days: 365);

  for (var index = 0; index < request.entries.length; index++) {
    final entry = request.entries[index];
    if (entry.password.isEmpty) {
      if (!entry.hasTotp) unprotectedAccounts.add(index);
    } else {
      passwordIndexes.putIfAbsent(entry.password, () => []).add(index);
      final strength = evaluatePasswordStrength(
        entry.password,
        userInputs: [entry.title, entry.username],
      );
      if (strength.isWeak) weakAccounts.add(index);
      if (!entry.hasTotp) withoutTotpAccounts.add(index);
    }

    final updatedAt = entry.updatedAt;
    if (updatedAt != null &&
        updatedAt > 0 &&
        request.nowMs - updatedAt >= staleAfter.inMilliseconds) {
      staleAccounts.add(index);
    }
  }

  final reusedAccounts = <int>[
    for (final indexes in passwordIndexes.values)
      if (indexes.length > 1) ...indexes,
  ]..sort();

  return PasswordAuditResult(
    totalAccounts: request.entries.length,
    reusedAccounts: reusedAccounts,
    weakAccounts: weakAccounts,
    staleAccounts: staleAccounts,
    unprotectedAccounts: unprotectedAccounts,
    withoutTotpAccounts: withoutTotpAccounts,
  );
}
