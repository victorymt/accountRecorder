import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/import/accountbox_importer.dart';

const _fixture = '''ACCOUNTBOX_JSON_13
{"version":13,"tagList":[{"tagName":"网盘"}],"accountList":[
{"name":"百度账号","accountItemList":[{"itemName":"账号","itemValue":"user1001"},{"itemName":"密码","itemValue":"P@ssw0rd"},{"itemName":"备注","itemValue":"找回邮箱备用"}],"tagList":[{"tagName":"网盘"}],"favorite":false,"lastEditTime":1734441234036},
{"name":"华为","accountItemList":[{"itemName":"账号","itemValue":"huawei@mail.com"},{"itemName":"密码","itemValue":"Hw!234"},{"itemName":"esc服务器密码","itemValue":"[3cXqYKZ2"}],"tagList":[{"tagName":"学校"},{"tagName":"网盘"}],"favorite":false},
{"name":"","accountItemList":[{"itemName":"账号","itemValue":"x"}],"tagList":[],"favorite":false},
{"name":"无账号项","accountItemList":[{"itemName":"密码","itemValue":"onlypwd"}],"tagList":[],"favorite":false}
]}''';

void main() {
  test('解析标准账号盒子文件', () {
    final accounts = AccountBoxImporter.parse(_fixture);
    expect(accounts, hasLength(3));

    expect(accounts[0].title, '百度账号');
    expect(accounts[0].username, 'user1001');
    expect(accounts[0].password, 'P@ssw0rd');
    expect(accounts[0].extra, contains('找回邮箱备用'));
    expect(accounts[0].tags, ['网盘']);
    expect(accounts[0].extra, isNot(contains('标签')));

    expect(accounts[1].title, '华为');
    expect(accounts[1].username, 'huawei@mail.com');
    expect(accounts[1].tags, ['学校', '网盘']);
    expect(accounts[1].extra, contains('esc服务器密码: [3cXqYKZ2'));

    expect(accounts[2].title, '无账号项');
    expect(accounts[2].username, '');
    expect(accounts[2].password, 'onlypwd');
  });

  test('无头文件时也能解析', () {
    final noHeader = _fixture.split('\n').skip(1).join('\n');
    final accounts = AccountBoxImporter.parse(noHeader);
    expect(accounts, hasLength(3));
  });

  test('空内容返回空列表', () {
    expect(AccountBoxImporter.parse(''), isEmpty);
    expect(AccountBoxImporter.parse('不是JSON'), isEmpty);
  });

  test('畸形列表结构不会触发类型转换异常', () {
    expect(AccountBoxImporter.parse('{"accountList":"invalid"}'), isEmpty);
    expect(
      AccountBoxImporter.parse(
        '{"accountList":[{"name":"账号","accountItemList":{},"tagList":[]}]}',
      ),
      isEmpty,
    );
    expect(
      AccountBoxImporter.parse(
        '{"accountList":[{"name":"账号","accountItemList":[],"tagList":{}}]}',
      ),
      isEmpty,
    );
  });

  test('账号数量超过上限时拒绝整个文件', () {
    final accounts = List.filled(
      AccountBoxImporter.maxAccountCount + 1,
      const <String, Object?>{'name': '账号'},
    );

    expect(
      () => AccountBoxImporter.parse('{"accountList":${jsonEncode(accounts)}}'),
      throwsA(isA<FormatException>()),
    );
  });
}
