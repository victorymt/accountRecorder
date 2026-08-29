import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'encrypted_vault_backup.dart';

/// Connection details for a WebDAV server.
class WebDavConfig {
  const WebDavConfig({
    required this.endpoint,
    required this.username,
    required this.password,
    required this.remotePath,
  });

  final String endpoint;
  final String username;
  final String password;
  final String remotePath;

  bool get isConfigured =>
      endpoint.trim().isNotEmpty && remotePath.trim().isNotEmpty;
}

class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Small WebDAV transport used for uploading and downloading encrypted vaults.
///
/// The client deliberately does not know the vault password or plaintext
/// account data. Callers pass the already encrypted `.abvault` bytes.
class WebDavClient {
  WebDavClient(
    this.config, {
    HttpClient? httpClient,
    Duration timeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null,
       _timeout = timeout {
    _httpClient.connectionTimeout = timeout;
  }

  final WebDavConfig config;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final Duration _timeout;

  Uri get _endpointUri {
    final raw = config.endpoint.trim();
    Uri parsed;
    try {
      parsed = Uri.parse(raw);
    } catch (_) {
      throw const WebDavException('WebDAV 地址无效');
    }
    if ((parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const WebDavException('WebDAV 地址必须是有效的 HTTP(S) 地址');
    }
    return parsed;
  }

  Uri get _fileUri {
    final endpoint = _endpointUri;
    final path = config.remotePath.trim().replaceAll('\\', '/');
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty ||
        segments.any((segment) => segment == '.' || segment == '..')) {
      throw const WebDavException('远端文件路径无效');
    }
    final basePath = endpoint.path.endsWith('/')
        ? endpoint.path
        : '${endpoint.path}/';
    return endpoint.replace(path: '$basePath${segments.join('/')}');
  }

  String get _authorization {
    final credentials = utf8.encode('${config.username}:${config.password}');
    return 'Basic ${base64Encode(credentials)}';
  }

  Future<void> upload(List<int> bytes) async {
    if (!config.isConfigured) {
      throw const WebDavException('请先配置 WebDAV');
    }
    if (bytes.length > EncryptedVaultBackup.maxFileBytes) {
      throw const WebDavException('备份文件过大');
    }
    final response = await _send(
      'PUT',
      _fileUri,
      content: bytes,
      contentType: ContentType('application', 'octet-stream'),
    );
    await _expectSuccess(response);
  }

  Future<Uint8List> download() async {
    if (!config.isConfigured) {
      throw const WebDavException('请先配置 WebDAV');
    }
    final response = await _send('GET', _fileUri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _throwResponse(response);
    }
    return _readLimited(response, EncryptedVaultBackup.maxFileBytes);
  }

  /// Checks authentication and server reachability without requiring a file
  /// to exist at the configured remote path.
  Future<void> testConnection() async {
    if (!config.isConfigured) {
      throw const WebDavException('请先填写 WebDAV 地址和远端文件路径');
    }
    final response = await _send('OPTIONS', _endpointUri);
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      await _throwResponse(response);
    }
    await _expectSuccess(response);
  }

  Future<HttpClientResponse> _send(
    String method,
    Uri uri, {
    List<int>? content,
    ContentType? contentType,
  }) async {
    try {
      final request = await _httpClient.openUrl(method, uri).timeout(_timeout);
      // Do not forward credentials through an HTTP redirect to another host.
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, _authorization);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      if (content != null) {
        request.headers.contentType = contentType;
        request.contentLength = content.length;
        request.add(content);
      }
      return await request.close().timeout(_timeout);
    } on WebDavException {
      rethrow;
    } on TimeoutException {
      throw const WebDavException('WebDAV 请求超时');
    } on SocketException {
      throw const WebDavException('无法连接 WebDAV 服务器');
    } catch (_) {
      throw const WebDavException('WebDAV 请求失败');
    }
  }

  Future<void> _expectSuccess(HttpClientResponse response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _throwResponse(response);
    }
    try {
      await response.timeout(_timeout).drain<void>();
    } on TimeoutException {
      throw const WebDavException('WebDAV 请求超时');
    }
  }

  Future<Never> _throwResponse(HttpClientResponse response) async {
    final status = response.statusCode;
    try {
      await response.timeout(_timeout).drain<void>();
    } on TimeoutException {
      throw const WebDavException('WebDAV 请求超时');
    }
    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      throw WebDavException('WebDAV 账号或密码错误', statusCode: status);
    }
    if (status == HttpStatus.notFound) {
      throw WebDavException('WebDAV 远端文件不存在', statusCode: status);
    }
    throw WebDavException('WebDAV 服务器返回错误（$status）', statusCode: status);
  }

  Future<Uint8List> _readLimited(
    HttpClientResponse response,
    int maxBytes,
  ) async {
    final declaredLength = response.contentLength;
    if (declaredLength > maxBytes) {
      await response.drain<void>();
      throw const WebDavException('备份文件过大');
    }
    final output = BytesBuilder(copy: false);
    var length = 0;
    try {
      await for (final chunk in response.timeout(_timeout)) {
        length += chunk.length;
        if (length > maxBytes) {
          throw const WebDavException('备份文件过大');
        }
        output.add(chunk);
      }
      return output.takeBytes();
    } on TimeoutException {
      output.clear();
      throw const WebDavException('WebDAV 请求超时');
    } catch (_) {
      output.clear();
      rethrow;
    }
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close(force: true);
  }
}
