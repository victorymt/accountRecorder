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

  static const int maxFileBytes = 16 * 1024 * 1024;
  static const int maxAccountCount = 10000;

  /// 解析「账号盒子」导出文件（ACCOUNTBOX_JSON_13 头 + JSON）。
  /// 无法解析时返回空列表。
  static List<ImportAccount> parse(String content) {
    if (utf8.encode(content).length > maxFileBytes) {
      throw const FormatException('Import file is too large');
    }
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
    final Object? rawList = decoded is Map
        ? decoded['accountList']
        : decoded is List
        ? decoded
        : null;
    if (rawList is! List) return const [];
    if (rawList.length > maxAccountCount) {
      throw const FormatException('Too many accounts');
    }

    final result = <ImportAccount>[];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final rawTitle = raw['name'];
      if (rawTitle is! String) continue;
      final title = rawTitle.trim();
      if (title.isEmpty) continue;

      String username = '';
      String password = '';
      String? note;
      final others = <String>[];
      final rawItems = raw['accountItemList'];
      if (rawItems != null && rawItems is! List) continue;
      final items = rawItems is List ? rawItems : const [];
      for (final entry in items) {
        if (entry is! Map) continue;
        final rawName = entry['itemName'];
        final rawValue = entry['itemValue'];
        if (rawName is! String || rawValue is! String) continue;
        final name = rawName.trim();
        final value = rawValue;
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

      final rawTags = raw['tagList'];
      if (rawTags != null && rawTags is! List) continue;
      final tags = (rawTags is List ? rawTags : const [])
          .whereType<Map>()
          .map((tag) => tag['tagName'])
          .whereType<String>()
          .map((tag) => tag.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final extraParts = <String>[
        if (note != null && note.isNotEmpty) note,
        ...others,
      ];
      result.add(
        ImportAccount(
          title: title,
          username: username,
          password: password,
          extra: extraParts.join('\n'),
          tags: tags,
        ),
      );
    }
    return result;
  }
}
