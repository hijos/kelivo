import 'dart:convert';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/builtin_tools.dart';
import 'package:Kelivo/core/services/api/kimi_code_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ProviderConfig _config({
  String baseUrl = 'https://api.kimi.com/coding/v1',
  String apiKey = 'sk-test',
}) => ProviderConfig(
  id: 'kimi-code',
  enabled: true,
  name: 'Kimi Code',
  apiKey: apiKey,
  baseUrl: baseUrl,
  providerType: ProviderKind.openai,
);

void main() {
  test('recognizes both Kimi Code hosts and optional trailing slash', () {
    expect(BuiltInToolsHelper.isKimiCodeProvider(_config()), isTrue);
    expect(
      BuiltInToolsHelper.isKimiCodeProvider(
        _config(baseUrl: 'https://api.kimi.ai/coding/v1/'),
      ),
      isTrue,
    );
    expect(
      BuiltInToolsHelper.isKimiCodeProvider(
        _config(baseUrl: 'https://api.moonshot.cn/v1'),
      ),
      isFalse,
    );
    expect(
      BuiltInToolsHelper.supportsBuiltInSearchForModel(
        cfg: _config(),
        modelId: 'k3',
      ),
      isTrue,
    );
    expect(
      BuiltInToolsHelper.modelSettingsToolNames(_config()),
      containsAll({'WebSearch', 'FetchURL'}),
    );
  });

  test('derives search and fetch endpoints', () {
    final cfg = _config(baseUrl: 'https://api.kimi.com/coding/v1/');
    expect(
      KimiCodeSearch.endpointFor(cfg, 'search').toString(),
      'https://api.kimi.com/coding/v1/search',
    );
    expect(
      KimiCodeSearch.endpointFor(cfg, 'fetch').toString(),
      'https://api.kimi.com/coding/v1/fetch',
    );
    expect(
      KimiCodeSearch.endpointFor(
        _config(baseUrl: 'https://api.moonshot.cn/v1'),
        'search',
      ),
      isNull,
    );
  });

  test('sends WebSearch request with bearer key and query body', () async {
    late http.Request request;
    final client = MockClient((incoming) async {
      request = incoming;
      return http.Response(jsonEncode({'items': []}), 200);
    });

    final result = await KimiCodeSearch.webSearch(
      client: client,
      config: _config(),
      query: 'latest news',
    );

    expect(request.method, 'POST');
    expect(request.url.path, '/coding/v1/search');
    expect(request.headers['authorization'], 'Bearer sk-test');
    expect(jsonDecode(request.body), {
      'text_query': 'latest news',
      'limit': 10,
      'enable_page_crawling': true,
      'timeout_seconds': 30,
    });
    expect(jsonDecode(result), {'items': []});
  });

  test('sends FetchURL request with url body', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/coding/v1/fetch');
      expect(jsonDecode(request.body), {'url': 'https://example.com'});
      return http.Response('# Example\n\nFetched content', 200);
    });

    expect(
      await KimiCodeSearch.fetchUrl(
        client: client,
        config: _config(),
        url: 'https://example.com',
      ),
      '# Example\n\nFetched content',
    );
  });

  test('rejects invalid FetchURL inputs before making a request', () async {
    final client = MockClient((_) async {
      fail('invalid URLs must not reach the network');
    });

    for (final url in const ['', 'example.com', 'ftp://example.com']) {
      await expectLater(
        KimiCodeSearch.fetchUrl(client: client, config: _config(), url: url),
        throwsA(
          isA<KimiCodeSearchException>().having(
            (error) => error.message,
            'message',
            contains('absolute http(s) URL'),
          ),
        ),
      );
    }
  });

  test('forwards the model tool call id to the Kimi service', () async {
    late http.Request request;
    final client = MockClient((incoming) async {
      request = incoming;
      return http.Response('# Example', 200);
    });

    await KimiCodeSearch.fetchUrl(
      client: client,
      config: _config(),
      url: 'https://example.com',
      toolCallId: 'call_fetch_123',
    );

    expect(request.headers['x-msh-tool-call-id'], 'call_fetch_123');
  });

  test('retries transient FetchURL server errors', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      if (attempts == 1) return http.Response('{"message":"temporary"}', 500);
      return http.Response('# recovered', 200);
    });

    expect(
      await KimiCodeSearch.fetchUrl(
        client: client,
        config: _config(),
        url: 'https://example.com',
        retryDelay: Duration.zero,
      ),
      '# recovered',
    );
    expect(attempts, 2);
  });

  test('truncates oversized FetchURL responses', () async {
    final client = MockClient(
      (_) async =>
          http.Response('x' * (KimiCodeSearch.maxResponseChars + 100), 200),
    );

    final result = await KimiCodeSearch.fetchUrl(
      client: client,
      config: _config(),
      url: 'https://example.com',
    );

    expect(result, contains('FetchURL content truncated'));
    expect(result.length, lessThanOrEqualTo(KimiCodeSearch.maxResponseChars));
  });

  test('reports HTTP, empty and malformed responses', () async {
    final cfg = _config();
    await expectLater(
      KimiCodeSearch.webSearch(
        client: MockClient((_) async => http.Response('{"message":"no"}', 500)),
        config: cfg,
        query: 'q',
        maxAttempts: 1,
      ),
      throwsA(isA<KimiCodeSearchException>()),
    );
    await expectLater(
      KimiCodeSearch.webSearch(
        client: MockClient((_) async => http.Response('', 200)),
        config: cfg,
        query: 'q',
      ),
      throwsA(isA<KimiCodeSearchException>()),
    );
    await expectLater(
      KimiCodeSearch.webSearch(
        client: MockClient((_) async => http.Response('not-json', 200)),
        config: cfg,
        query: 'q',
      ),
      throwsA(isA<KimiCodeSearchException>()),
    );
  });

  test('reports request timeout', () async {
    await expectLater(
      KimiCodeSearch.webSearch(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response('{}', 200);
        }),
        config: _config(),
        query: 'q',
        timeout: const Duration(milliseconds: 5),
        maxAttempts: 1,
      ),
      throwsA(isA<KimiCodeSearchException>()),
    );
  });

  test('merges fixed Kimi Code tool declarations without collisions', () {
    final body = <String, dynamic>{
      'tools': [
        {
          'type': 'function',
          'function': {'name': 'WebSearch', 'description': 'custom'},
        },
      ],
    };
    final inserted = KimiCodeSearch.mergeTools(body);
    expect(inserted, {'FetchURL'});
    expect(
      (body['tools'] as List)
          .map((e) => (e as Map)['function']['name'])
          .toSet(),
      {'WebSearch', 'FetchURL'},
    );
  });

  test('can merge only explicitly selected Kimi Code tools', () {
    final body = <String, dynamic>{};
    expect(KimiCodeSearch.mergeTools(body, enabledNames: {'WebSearch'}), {
      'WebSearch',
    });
    expect((body['tools'] as List).single['function']['name'], 'WebSearch');
  });
}
