import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/backup/webdav_backup.dart';

void main() {
  late HttpServer server;
  late Uri endpoint;
  late Uint8List stored;
  late String? lastAuthorization;
  final requests = <String>[];

  setUp(() async {
    stored = Uint8List(0);
    lastAuthorization = null;
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://${server.address.host}:${server.port}/dav');
    server.listen((request) async {
      requests.add(request.method);
      lastAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        final body = BytesBuilder(copy: false);
        await for (final chunk in request) {
          body.add(chunk);
        }
        stored = body.takeBytes();
        request.response.statusCode = HttpStatus.created;
        await request.response.close();
        return;
      }
      if (request.method == 'GET') {
        request.response.headers.contentType = ContentType(
          'application',
          'octet-stream',
        );
        request.response.add(stored);
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test(
    'uploads and downloads encrypted backup bytes with basic auth',
    () async {
      final client = WebDavClient(
        WebDavConfig(
          endpoint: endpoint.toString(),
          username: 'alice',
          password: 'secret',
          remotePath: 'backups/account-book.abvault',
        ),
      );
      addTearDown(client.close);

      await client.testConnection();
      final payload = Uint8List.fromList(utf8.encode('encrypted payload'));
      await client.upload(payload);
      expect(await client.download(), payload);
      expect(requests, ['OPTIONS', 'PUT', 'GET']);
      expect(
        lastAuthorization,
        'Basic ${base64Encode(utf8.encode('alice:secret'))}',
      );
    },
  );

  test('rejects invalid paths before making a request', () async {
    final client = WebDavClient(
      WebDavConfig(
        endpoint: endpoint.toString(),
        username: '',
        password: '',
        remotePath: '../outside.abvault',
      ),
    );
    addTearDown(client.close);

    expect(client.download, throwsA(isA<WebDavException>()));
    expect(requests, isEmpty);
  });

  test('maps unauthorized responses to a credential error', () async {
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://${server.address.host}:${server.port}/dav');
    server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });
    final client = WebDavClient(
      WebDavConfig(
        endpoint: endpoint.toString(),
        username: 'alice',
        password: 'wrong',
        remotePath: 'account-book.abvault',
      ),
    );
    addTearDown(client.close);

    expect(
      client.testConnection,
      throwsA(
        isA<WebDavException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.unauthorized,
        ),
      ),
    );
  });
}
