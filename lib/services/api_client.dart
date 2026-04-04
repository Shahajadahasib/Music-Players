import 'dart:convert';

import 'package:http/http.dart' as http;

/// A thin, reusable HTTP wrapper used by services that need structured JSON
/// responses (e.g. [JamendoService] or future endpoints).
///
/// Some services make raw `http` calls for full control over query parameters.
/// This client exists for endpoints that don't need custom per-call auth logic,
/// and as a centralised place to adjust timeouts, logging, or retry strategy.
///
/// ## Error handling contract
///
/// All methods throw an [ApiException] when:
///   - A network-level error occurs (socket, DNS, timeout).
///   - The HTTP status code is not in the 2xx range.
///   - The response body cannot be decoded as JSON.
///
/// Callers catch [ApiException] and translate it into user-facing messages.
class ApiClient {
  const ApiClient({http.Client? client}) : _client = client;

  /// Allows injecting a mock client in tests. Defaults to the global http
  /// functions when null.
  final http.Client? _client;

  // ── GET ───────────────────────────────────────────────────────────────────

  /// Sends a GET request and returns the decoded JSON body.
  ///
  /// [uri]     — the fully-formed request URI, including query parameters.
  /// [headers] — optional HTTP headers (e.g. `Authorization: Bearer …`).
  Future<Map<String, dynamic>> get(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final http.Response response;
    try {
      response = _client != null
          ? await _client.get(uri, headers: headers)
          : await http.get(uri, headers: headers);
    } on Exception catch (e) {
      throw ApiException('Network error on GET $uri — $e');
    }
    return _decode(response);
  }

  // ── POST ──────────────────────────────────────────────────────────────────

  /// Sends a POST request and returns the decoded JSON body.
  ///
  /// [uri]     — the request URI.
  /// [headers] — optional HTTP headers (Content-Type is set here when needed).
  /// [body]    — the raw request body (typically
  ///             `application/x-www-form-urlencoded` for OAuth2 token calls).
  Future<Map<String, dynamic>> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final http.Response response;
    try {
      response = _client != null
          ? await _client.post(uri, headers: headers, body: body)
          : await http.post(uri, headers: headers, body: body);
    } on Exception catch (e) {
      throw ApiException('Network error on POST $uri — $e');
    }
    return _decode(response);
  }

  // ── Decoding + status validation ──────────────────────────────────────────

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'HTTP ${response.statusCode} — ${response.reasonPhrase ?? 'Unknown'}: '
        '${_truncate(response.body)}',
        statusCode: response.statusCode,
      );
    }

    if (response.body.isEmpty) {
      throw const ApiException('Received an empty response body.');
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const ApiException('Expected a JSON object but got a different type.');
      }
      return decoded;
    } on FormatException catch (e) {
      throw ApiException('Failed to decode JSON: $e');
    }
  }

  /// Keeps error messages readable when the server returns a large HTML body.
  static String _truncate(String text, {int maxLength = 200}) =>
      text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';
}

// ── Exception ─────────────────────────────────────────────────────────────────

/// Thrown by [ApiClient] for any network, HTTP, or JSON error.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// The HTTP status code if the error was a non-2xx response; otherwise null.
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode != null && statusCode! >= 500;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
