import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class UploadException implements Exception {
  const UploadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// HTTP client for the study upload server (server/ in the repository).
class UploadClient {
  UploadClient(String baseUrl, this._token, {HttpClient? http})
    : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
      _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final Uri _base;
  final String _token;
  final HttpClient _http;

  /// Sends one photo. A photo the server already holds is accepted again.
  Future<void> putPhoto(String file, File source, Map<String, Object?> meta) async {
    final bytes = await source.readAsBytes();
    await _put(Uri.parse('${_base}v1/photos/$file'), bytes, {
      'Content-Type': 'image/jpeg',
      'X-Sha256': sha256.convert(bytes).toString(),
      'X-Meta': _asciiJson(meta),
    });
  }

  Future<void> putAnimal(String identity, Map<String, Object?> log) => _put(
    _base.resolve('v1/animals/$identity'),
    utf8.encode(jsonEncode(log)),
    {'Content-Type': 'application/json'},
  );

  Future<void> _put(Uri uri, List<int> body, Map<String, String> headers) async {
    try {
      final request = await _http.putUrl(uri);
      request.headers.set('Authorization', 'Bearer $_token');
      headers.forEach(request.headers.set);
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(const Duration(minutes: 2));
      await response.drain<void>();
      switch (response.statusCode) {
        case >= 200 && < 300:
          return;
        case 401:
          throw const UploadException('The server did not accept the upload key.');
        case 409:
          throw const UploadException('The server has a different photo with the same name.');
        case final code:
          throw UploadException('The server returned an error ($code).');
      }
    } on SocketException {
      throw const UploadException('No connection to the server. Try again when online.');
    } on TimeoutException {
      throw const UploadException('The upload timed out. Try again on a better connection.');
    } on HandshakeException {
      throw const UploadException('Secure connection to the server failed.');
    }
  }

  void close() => _http.close(force: true);
}

/// HTTP headers must be ASCII, so any other character is escaped inside the JSON.
String _asciiJson(Map<String, Object?> value) => jsonEncode(value).replaceAllMapped(
  RegExp(r'[^\x20-\x7e]'),
  (m) => '\\u${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
);
