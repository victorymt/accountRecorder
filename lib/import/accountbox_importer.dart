import 'dart:convert';

class ImportAccount {
  ImportAccount({
    required this.title,
    required this.username,
    required this.password,
    required this.extra,
    required this.tags,
  });

  final String title;
  final String username;
  final String password;
  final String extra;
  final List<String> tags;
}

class AccountBoxImporter {
  AccountBoxImporter._();

  /// 解析「账号盒子」导出文件（ACCOUNTBOX_JSON_13 头 + JSON）。
  /// 无法解析时返回空列表。
  static List<ImportAccount> parse(String content) {
    var body = content;
    final firstNewline = content.indexOf('\n');
    if (firstNewline > 0) {
      final header = content.substring(0, firstNewline).trim();
      if (header.startsWith('ACCOUNTBOX_JSON')) {
        body = content.substring(firstNewline + 1);
      }
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const [];
    }
    final list = decoded is Map<String, dynamic>
        ? (decoded['accountList'] as List<dynamic>? ?? [])
        : decoded is List ? decoded : <dynamic>[];

    final result = <ImportAccount>[];
    for (final raw in list) {
      if (raw is! Map<String, dynamic>) continue;
      final title = (raw['name'] as String? ?? '').trim();
      if (title.isEmpty) continue;

      String username = '';
      String password = '';
      String? note;
      final others = <String>[];
      final items = raw['accountItemList'] as List<dynamic>? ?? [];
      for (final entry in items) {
        if (entry is! Map<String, dynamic>) continue;
        final name = (entry['itemName'] as String? ?? '').trim();
        final value = entry['itemValue'] as String? ?? '';
        switch (name) {
          case '账号':
            username = value.trim();
          case '密码':
            password = value;
          case '备注':
            note = value;
          default:
            if (name.isNotEmpty) others.add('$name: $value');
        }
      }

      final tags = (raw['tagList'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((t) => (t['tagName'] as String? ?? '').trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final extraParts = <String>[
        if (note != null && note.isNotEmpty) note,
        ...others,
      ];
      result.add(ImportAccount(
        title: title,
        username: username,
        password: password,
        extra: extraParts.join('\n'),
        tags: tags,
      ));
    }
    return result;
  }
}
