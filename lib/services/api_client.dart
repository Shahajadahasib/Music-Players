import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Small JSON-over-HTTP client shared by all music sources.
///
/// * Per-request timeout so one slow provider cannot stall search.
/// * One retry with back-off for transient failures (5xx / network), never for
///   4xx — retrying a 429 immediately only makes rate limiting worse.
/// * Injectable [http.Client] so tests run against `MockClient` without
///   touching the network.
class ApiClient {
  ApiClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.retries = 1,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int retries;

  Future<Map<String, dynamic>> get(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final decoded = await getJson(uri, headers: headers);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Expected a JSON object.');
    }
    return decoded;
  }

  Future<Object?> getJson(Uri uri, {Map<String, String>? headers}) async {
    final response = await _send(() => _client.get(uri, headers: headers));
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response =
        await _send(() => _client.post(uri, headers: headers, body: body));
    final decoded = _decode(response);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Expected a JSON object.');
    }
    return decoded;
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await request().timeout(timeout);
        final transient = response.statusCode >= 500;
        if (transient && attempt < retries) {
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt < retries) {
          attempt++;
          continue;
        }
        throw const ApiException('Request timed out.', isNetwork: true);
      } on ApiException {
        rethrow;
      } catch (e) {
        if (attempt < retries) {
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        throw ApiException('Network error: $e', isNetwork: true);
      }
    }
  }

  Object? _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'HTTP ${response.statusCode}: ${_truncate(response.body)}',
        statusCode: response.statusCode,
      );
    }
    if (response.body.isEmpty) {
      throw const ApiException('Received an empty response body.');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw ApiException('Failed to decode JSON: $e');
    }
  }

  static String _truncate(String text, {int maxLength = 200}) =>
      text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';

  void close() => _client.close();
}

/// Thrown by [ApiClient] for any network, HTTP, or JSON error.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.isNetwork = false});

  final String message;
  final int? statusCode;
  final bool isNetwork;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get isServerError => statusCode != null && statusCode! >= 500;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
