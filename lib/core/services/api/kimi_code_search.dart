import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../providers/settings_provider.dart';

/// HTTP bridge for Kimi Code's hosted WebSearch and FetchURL tools.
///
/// Kimi Code exposes these services next to the OpenAI-compatible
/// `/chat/completions` endpoint. The same provider API key authenticates all
/// three endpoints, so no additional search configuration is required.
class KimiCodeSearch {
  static const String webSearchToolName = 'WebSearch';
  static const String fetchUrlToolName = 'FetchURL';
  static const Duration defaultTimeout = Duration(seconds: 60);
  static const Duration defaultRetryDelay = Duration(seconds: 1);
  static const int defaultMaxAttempts = 3;
  static const int maxResponseChars = 100000;
  static const int maxErrorChars = 8192;

  static List<Map<String, dynamic>> toolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': webSearchToolName,
        'description': 'Search the web for current information.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Search terms to look up online',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': fetchUrlToolName,
        'description': 'Fetch and extract the contents of a web page.',
        'parameters': {
          'type': 'object',
          'properties': {
            'url': {'type': 'string', 'description': 'The URL to fetch'},
          },
          'required': ['url'],
        },
      },
    },
  ];

  /// Inserts Kimi Code tools without replacing user-provided declarations.
  /// Returns only names actually inserted, for safe dispatch routing.
  static Set<String> mergeTools(
    Map<String, dynamic> body, {
    Iterable<String>? enabledNames,
  }) {
    final enabled = enabledNames == null
        ? <String>{webSearchToolName, fetchUrlToolName}
        : enabledNames.toSet();
    final existing = body['tools'];
    final tools = <Map<String, dynamic>>[
      if (existing is List)
        for (final entry in existing)
          if (entry is Map) entry.cast<String, dynamic>(),
    ];
    final names = <String>{
      for (final tool in tools)
        if (tool['function'] is Map)
          ((tool['function'] as Map)['name'] ?? '').toString().trim(),
    };
    final inserted = <String>{};
    for (final tool in toolDefinitions().where(
      (tool) => enabled.contains((tool['function'] as Map)['name']),
    )) {
      final name = ((tool['function'] as Map)['name'] ?? '').toString();
      if (names.contains(name)) continue;
      tools.add(tool);
      names.add(name);
      inserted.add(name);
    }
    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] ??= 'auto';
    }
    return inserted;
  }

  static Uri? endpointFor(ProviderConfig config, String suffix) {
    final uri = Uri.tryParse(config.baseUrl.trim());
    if (uri == null) return null;
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (uri.host.toLowerCase() != 'api.kimi.com' &&
        uri.host.toLowerCase() != 'api.kimi.ai') {
      return null;
    }
    if (path != '/coding/v1') return null;
    return uri.replace(path: '$path/$suffix');
  }

  static Future<String> webSearch({
    required http.Client client,
    required ProviderConfig config,
    required String query,
    Duration timeout = defaultTimeout,
    String? apiKey,
    String? toolCallId,
    int maxAttempts = defaultMaxAttempts,
    Duration retryDelay = defaultRetryDelay,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw const KimiCodeSearchException('WebSearch requires a query');
    }
    return _post(
      client: client,
      config: config,
      suffix: 'search',
      payload: {
        'text_query': normalizedQuery,
        'limit': 10,
        'enable_page_crawling': true,
        'timeout_seconds': 30,
      },
      operation: 'WebSearch',
      timeout: timeout,
      apiKey: apiKey,
      toolCallId: toolCallId,
      maxAttempts: maxAttempts,
      retryDelay: retryDelay,
      responseFormat: _KimiCodeResponseFormat.json,
    );
  }

  static Future<String> fetchUrl({
    required http.Client client,
    required ProviderConfig config,
    required String url,
    Duration timeout = defaultTimeout,
    String? apiKey,
    String? toolCallId,
    int maxAttempts = defaultMaxAttempts,
    Duration retryDelay = defaultRetryDelay,
  }) async {
    final normalizedUrl = _validateFetchUrl(url);
    return _post(
      client: client,
      config: config,
      suffix: 'fetch',
      payload: {'url': normalizedUrl},
      operation: 'FetchURL',
      timeout: timeout,
      apiKey: apiKey,
      toolCallId: toolCallId,
      maxAttempts: maxAttempts,
      retryDelay: retryDelay,
      responseFormat: _KimiCodeResponseFormat.text,
    );
  }

  static Future<String> _post({
    required http.Client client,
    required ProviderConfig config,
    required String suffix,
    required Map<String, dynamic> payload,
    required String operation,
    required Duration timeout,
    required _KimiCodeResponseFormat responseFormat,
    String? apiKey,
    String? toolCallId,
    required int maxAttempts,
    required Duration retryDelay,
  }) async {
    final uri = endpointFor(config, suffix);
    if (uri == null) {
      throw KimiCodeSearchException(
        '$operation is only available for a Kimi Code /coding/v1 endpoint',
      );
    }
    final key = (apiKey ?? config.apiKey).trim();
    if (key.isEmpty) {
      throw KimiCodeSearchException('$operation requires a provider API key');
    }

    final callId = toolCallId?.trim();
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    final delay = retryDelay.isNegative ? Duration.zero : retryDelay;
    final headers = {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'X-Msh-Tool-Call-Id': callId == null || callId.isEmpty
          ? 'kelivo-${DateTime.now().microsecondsSinceEpoch}'
          : callId,
      'Accept': responseFormat == _KimiCodeResponseFormat.text
          ? 'text/markdown, text/plain, application/json'
          : 'application/json',
    };

    http.Response response;
    for (var attempt = 1; ; attempt++) {
      try {
        response = await client
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(timeout);
      } on TimeoutException {
        if (attempt >= attempts) {
          throw KimiCodeSearchException('$operation request timed out');
        }
        await Future<void>.delayed(delay);
        continue;
      } catch (error) {
        if (attempt >= attempts) {
          throw KimiCodeSearchException('$operation request failed: $error');
        }
        await Future<void>.delayed(delay);
        continue;
      }
      if (!_isRetryableStatus(response.statusCode) || attempt >= attempts) {
        break;
      }
      await Future<void>.delayed(delay);
    }

    final body = response.body.trim();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KimiCodeSearchException(
        '$operation failed (${response.statusCode}): ${_errorDetail(body)}',
      );
    }
    if (body.isEmpty) {
      throw KimiCodeSearchException('$operation returned an empty response');
    }
    if (responseFormat == _KimiCodeResponseFormat.text) {
      return _truncate(body, maxResponseChars, 'FetchURL content truncated');
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('expected a JSON object');
      }
      return jsonEncode(decoded);
    } on FormatException catch (error) {
      throw KimiCodeSearchException(
        '$operation returned malformed JSON: $error',
      );
    }
  }

  static String _errorDetail(String body) {
    if (body.isEmpty) return 'empty response';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        for (final key in const ['error', 'message', 'msg', 'detail']) {
          final value = decoded[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            final detail = value is String ? value : jsonEncode(value);
            return _truncate(detail, maxErrorChars, 'error response truncated');
          }
        }
      }
    } catch (_) {
      // Preserve a short plain-text server error when it is not JSON.
    }
    return _truncate(body, maxErrorChars, 'error response truncated');
  }

  static bool _isRetryableStatus(int statusCode) =>
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  static String _validateFetchUrl(String rawUrl) {
    final url = rawUrl.trim();
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      throw const KimiCodeSearchException(
        'FetchURL requires an absolute http(s) URL',
      );
    }
    return url;
  }

  static String _truncate(String value, int limit, String marker) {
    if (value.length <= limit) return value;
    final suffix = '\n\n[$marker after $limit characters]';
    var end = limit - suffix.length;
    if (end < 0) end = 0;
    if (end > 0 && end < value.length) {
      final codeUnit = value.codeUnitAt(end - 1);
      if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) end--;
    }
    return '${value.substring(0, end)}$suffix';
  }
}

enum _KimiCodeResponseFormat { json, text }

class KimiCodeSearchException implements Exception {
  const KimiCodeSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}
