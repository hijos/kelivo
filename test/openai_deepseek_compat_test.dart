import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/model_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/builtin_tools.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/api/openai_compatible_url.dart';

ProviderConfig _deepSeekConfig(
  String baseUrl, {
  bool useResponseApi = false,
  String modelId = 'deepseek-v4-flash',
  bool builtInSearch = false,
}) {
  return ProviderConfig(
    id: 'DeepSeekCompatTest',
    enabled: true,
    name: 'DeepSeekCompatTest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
    useResponseApi: useResponseApi,
    modelOverrides: <String, dynamic>{
      modelId: <String, dynamic>{
        'abilities': const <String>['tool', 'reasoning'],
        if (builtInSearch)
          'builtInTools': const <String>[BuiltInToolNames.search],
      },
    },
  );
}

Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
  return jsonDecode(await utf8.decoder.bind(request).join())
      as Map<String, dynamic>;
}

class _ProxyHttpOverrides extends HttpOverrides {
  _ProxyHttpOverrides(this.port);

  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
    return client;
  }
}

void main() {
  group('DeepSeek OpenAI compatibility', () {
    test('built-in search is available for every DeepSeek Responses model', () {
      final responsesConfig = _deepSeekConfig(
        'https://api.deepseek.com/v1',
        useResponseApi: true,
        modelId: 'deepseek-future-model',
      );
      final chatConfig = _deepSeekConfig(
        'https://api.deepseek.com/v1',
        modelId: 'deepseek-future-model',
      );
      final otherProvider = ProviderConfig(
        id: 'OtherProvider',
        enabled: true,
        name: 'OtherProvider',
        apiKey: 'test-key',
        baseUrl: 'https://example.com/v1',
        providerType: ProviderKind.openai,
        useResponseApi: true,
      );
      final thirdPartyDeepSeek = ProviderConfig(
        id: 'axonhub-gpt',
        enabled: true,
        name: 'axonhub-gpt',
        apiKey: 'test-key',
        baseUrl: 'https://axonhub.example/v1',
        providerType: ProviderKind.openai,
        useResponseApi: true,
      );

      expect(
        BuiltInToolsHelper.supportsBuiltInSearchForModel(
          cfg: responsesConfig,
          modelId: 'deepseek-future-model',
        ),
        isTrue,
      );
      expect(
        BuiltInToolsHelper.supportsBuiltInSearchForModel(
          cfg: chatConfig,
          modelId: 'deepseek-future-model',
        ),
        isFalse,
      );
      expect(
        BuiltInToolsHelper.supportsBuiltInSearchForModel(
          cfg: otherProvider,
          modelId: 'custom-model',
        ),
        isFalse,
      );
      expect(
        BuiltInToolsHelper.isDeepSeekProvider(thirdPartyDeepSeek),
        isFalse,
      );
      expect(
        BuiltInToolsHelper.supportsBuiltInSearchForModel(
          cfg: thirdPartyDeepSeek,
          modelId: 'deepseek-v4-flash',
        ),
        isTrue,
      );
    });

    test('third-party DeepSeek Responses request injects web_search', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      Map<String, dynamic>? receivedBody;
      String? receivedPath;
      server.listen((request) async {
        receivedPath = request.uri.path;
        receivedBody = await _readJsonBody(request);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'output_text': 'ok',
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        );
        await request.response.close();
      });

      final modelId = 'deepseek-v4-flash';
      final config = ProviderConfig(
        id: 'axonhub-gpt',
        enabled: true,
        name: 'axonhub-gpt',
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.address}:${server.port}/v1',
        providerType: ProviderKind.openai,
        useResponseApi: true,
        modelOverrides: <String, dynamic>{
          modelId: <String, dynamic>{
            'abilities': const <String>['tool', 'reasoning'],
            'builtInTools': const <String>[BuiltInToolNames.search],
            'webSearch': <String, dynamic>{
              'preview': true,
              'allowed_domains': const <String>['example.com'],
            },
          },
        },
      );

      final chunks = await ChatApiService.sendMessageStream(
        config: config,
        modelId: modelId,
        messages: const <Map<String, dynamic>>[
          {'role': 'user', 'content': 'Search'},
        ],
        stream: false,
      ).toList();

      expect(receivedPath, '/v1/responses');
      expect(receivedBody!['tools'], [
        {'type': 'web_search'},
      ]);
      expect(chunks.last.isDone, isTrue);
    });

    test('custom DeepSeek relays keep their configured v1 path', () {
      final config = _deepSeekConfig(
        'https://relay.example.com/v1',
        useResponseApi: true,
      );

      expect(
        resolveOpenAICompatibleUrl(config).toString(),
        'https://relay.example.com/v1/responses',
      );
    });

    test(
      'Responses stream uses root endpoint, built-in search, reasoning, and citations',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        Map<String, dynamic>? receivedBody;
        String? receivedPath;
        String? authorization;
        server.listen((request) async {
          receivedPath = request.uri.path;
          authorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          receivedBody = await _readJsonBody(request);
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.write(
            'event: response.reasoning_text.delta\n'
            'data: ${jsonEncode({'type': 'response.reasoning_text.delta', 'sequence_number': 1, 'delta': 'thinking'})}\n\n',
          );
          request.response.write(
            'event: response.output_text.delta\n'
            'data: ${jsonEncode({'type': 'response.output_text.delta', 'sequence_number': 2, 'delta': 'answer'})}\n\n',
          );
          request.response.write(
            'event: response.completed\n'
            'data: ${jsonEncode({
              'type': 'response.completed',
              'sequence_number': 3,
              'response': {
                'status': 'completed',
                'usage': {'input_tokens': 5, 'output_tokens': 7, 'total_tokens': 12},
                'output': [
                  {
                    'type': 'web_search_call',
                    'id': 'ws_1',
                    'status': 'completed',
                    'action': {'type': 'search', 'query': 'Kelivo'},
                  },
                  {
                    'type': 'message',
                    'role': 'assistant',
                    'content': [
                      {
                        'type': 'output_text',
                        'text': 'answer',
                        'annotations': [
                          {'type': 'url_citation', 'url': 'https://example.com/source', 'title': 'Example source'},
                        ],
                      },
                    ],
                  },
                ],
              },
            })}\n\n',
          );
          await request.response.close();
        });

        final chunks = await HttpOverrides.runZoned(
          () => ChatApiService.sendMessageStream(
            config: _deepSeekConfig(
              'http://api.deepseek.com/v1',
              useResponseApi: true,
              builtInSearch: true,
            ),
            modelId: 'deepseek-v4-flash',
            messages: const <Map<String, dynamic>>[
              {'role': 'user', 'content': 'Search for Kelivo'},
            ],
            thinkingBudget: 64000,
          ).toList(),
          createHttpClient: (context) {
            return _ProxyHttpOverrides(server.port).createHttpClient(context);
          },
        );

        expect(receivedPath, '/responses');
        expect(authorization, 'Bearer test-key');
        expect(receivedBody!['model'], 'deepseek-v4-flash');
        expect(receivedBody!['reasoning'], {
          'summary': 'auto',
          'effort': 'xhigh',
        });
        expect(receivedBody!['tools'], [
          {'type': 'web_search'},
        ]);
        expect(chunks.map((chunk) => chunk.reasoning ?? '').join(), 'thinking');
        expect(chunks.map((chunk) => chunk.content).join(), 'answer');
        final searchResult = chunks
            .expand((chunk) => chunk.toolResults ?? const <ToolResultInfo>[])
            .single;
        expect(searchResult.name, 'search_web');
        expect(jsonDecode(searchResult.content), {
          'items': [
            {
              'index': 1,
              'url': 'https://example.com/source',
              'title': 'Example source',
            },
          ],
        });
        expect(chunks.last.isDone, isTrue);
        expect(chunks.last.totalTokens, 12);
      },
    );

    test('connection test uses the same root Responses endpoint', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      String? receivedPath;
      server.listen((request) async {
        receivedPath = request.uri.path;
        await _readJsonBody(request);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'ok'},
                ],
              },
            ],
          }),
        );
        await request.response.close();
      });

      await HttpOverrides.runZoned(
        () => ProviderManager.testConnection(
          _deepSeekConfig('http://api.deepseek.com/v1', useResponseApi: true),
          'deepseek-v4-flash',
        ),
        createHttpClient: (context) {
          return _ProxyHttpOverrides(server.port).createHttpClient(context);
        },
      );

      expect(receivedPath, '/responses');
    });

    test(
      'incomplete Responses event preserves partial output and usage',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((request) async {
          await _readJsonBody(request);
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.write(
            'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'partial'})}\n\n',
          );
          request.response.write(
            'data: ${jsonEncode({
              'type': 'response.incomplete',
              'response': {
                'status': 'incomplete',
                'incomplete_details': {'reason': 'max_output_tokens'},
                'usage': {'input_tokens': 2, 'output_tokens': 3},
                'output': const <dynamic>[],
              },
            })}\n\n',
          );
          await request.response.close();
        });

        final baseUrl = 'http://${server.address.address}:${server.port}/v1';
        final chunks = await ChatApiService.sendMessageStream(
          config: _deepSeekConfig(baseUrl, useResponseApi: true),
          modelId: 'deepseek-v4-flash',
          messages: const <Map<String, dynamic>>[
            {'role': 'user', 'content': 'hello'},
          ],
        ).toList();

        expect(chunks.map((chunk) => chunk.content).join(), 'partial');
        expect(chunks.last.isDone, isTrue);
        expect(chunks.last.totalTokens, 5);
      },
    );

    test('failed Responses event surfaces the API error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        await _readJsonBody(request);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: ${jsonEncode({
            'type': 'response.failed',
            'response': {
              'status': 'failed',
              'error': {'code': 'server_error', 'message': 'try again'},
            },
          })}\n\n',
        );
        await request.response.close();
      });

      final baseUrl = 'http://${server.address.address}:${server.port}/v1';
      expect(
        () => ChatApiService.sendMessageStream(
          config: _deepSeekConfig(baseUrl, useResponseApi: true),
          modelId: 'deepseek-v4-flash',
          messages: const <Map<String, dynamic>>[
            {'role': 'user', 'content': 'hello'},
          ],
        ).toList(),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            contains('server_error: try again'),
          ),
        ),
      );
    });

    test(
      'xhigh reasoning keeps thinking enabled and passes xhigh effort',
      () async {
        final requests = <Map<String, dynamic>>[];

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((request) async {
          requests.add(await _readJsonBody(request));
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.write(
            'data: ${jsonEncode({
              'id': 'cmpl-deepseek',
              'object': 'chat.completion.chunk',
              'created': 0,
              'model': 'deepseek-v4-pro',
              'choices': [
                {
                  'index': 0,
                  'delta': {'role': 'assistant', 'content': 'ok'},
                  'finish_reason': 'stop',
                },
              ],
            })}\n\n',
          );
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        });

        final baseUrl = 'http://${server.address.address}:${server.port}/v1';
        final chunks = await ChatApiService.sendMessageStream(
          config: _deepSeekConfig(baseUrl),
          modelId: 'deepseek-v4-pro',
          messages: const [
            {'role': 'user', 'content': 'hello'},
          ],
          thinkingBudget: 64000,
        ).toList();

        expect(chunks.last.isDone, isTrue);
        expect(requests, hasLength(1));
        expect(requests.single['thinking'], {'type': 'enabled'});
        expect(requests.single['reasoning_effort'], 'xhigh');
      },
    );

    test('off reasoning disables thinking and strips effort', () async {
      final requests = <Map<String, dynamic>>[];

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        requests.add(await _readJsonBody(request));
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: ${jsonEncode({
            'id': 'cmpl-deepseek',
            'object': 'chat.completion.chunk',
            'created': 0,
            'model': 'deepseek-v4-pro',
            'choices': [
              {
                'index': 0,
                'delta': {'role': 'assistant', 'content': 'ok'},
                'finish_reason': 'stop',
              },
            ],
          })}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });

      final baseUrl = 'http://${server.address.address}:${server.port}/v1';
      final chunks = await ChatApiService.sendMessageStream(
        config: _deepSeekConfig(baseUrl),
        modelId: 'deepseek-v4-pro',
        messages: const [
          {'role': 'user', 'content': 'hello'},
        ],
        thinkingBudget: 0,
      ).toList();

      expect(chunks.last.isDone, isTrue);
      expect(requests, hasLength(1));
      expect(requests.single['thinking'], {'type': 'disabled'});
      expect(requests.single.containsKey('reasoning_effort'), isFalse);
    });
  });
}
