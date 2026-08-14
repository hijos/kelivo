import 'dart:convert';

import 'package:Kelivo/core/services/search/providers/openai_responses_search_service.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:Kelivo/utils/brand_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('OpenAI Responses search service', () {
    test('serializes options and resolves factory/icon mapping', () {
      final options = OpenAIResponsesOptions(
        id: 'openai-1',
        apiKey: 'openai-test',
        model: 'custom-model',
        customUrl: 'https://example.com/v1/responses',
        systemPrompt: 'Search carefully.',
        extraApiKeys: const ['openai-backup'],
      );

      final restored = SearchServiceOptions.fromJson(options.toJson());

      expect(restored, isA<OpenAIResponsesOptions>());
      final openai = restored as OpenAIResponsesOptions;
      expect(openai.id, 'openai-1');
      expect(openai.apiKey, 'openai-test');
      expect(openai.model, 'custom-model');
      expect(openai.customUrl, 'https://example.com/v1/responses');
      expect(openai.systemPrompt, 'Search carefully.');
      expect(openai.extraApiKeys, ['openai-backup']);
      expect(
        SearchService.getService(openai),
        isA<OpenAIResponsesSearchService>(),
      );
      expect(BrandAssets.assetForName('openai'), 'assets/icons/openai.svg');
    });

    test(
      'posts web search request and parses distinct URL citations',
      () async {
        http.Request? captured;
        final service = OpenAIResponsesSearchService(
          client: MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode({
                'output': [
                  {'type': 'web_search_call', 'status': 'completed'},
                  {
                    'type': 'message',
                    'role': 'assistant',
                    'content': [
                      {
                        'type': 'output_text',
                        'text': 'Kelivo is a Flutter chat client.',
                        'annotations': [
                          {
                            'type': 'url_citation',
                            'url': 'https://example.com/a',
                            'title': 'Example A',
                          },
                          {
                            'type': 'url_citation',
                            'url': 'https://example.com/a',
                            'title': 'Duplicate',
                          },
                          {
                            'type': 'url_citation',
                            'url': 'https://example.com/b',
                          },
                        ],
                      },
                    ],
                  },
                ],
              }),
              200,
            );
          }),
        );

        final result = await service.search(
          query: 'kelivo',
          commonOptions: const SearchCommonOptions(
            resultSize: 2,
            timeout: 1000,
          ),
          serviceOptions: OpenAIResponsesOptions(
            id: 'openai-1',
            apiKey: ' openai-test ',
            model: 'custom-model',
            customUrl: 'https://example.com/v1/responses',
            systemPrompt: 'Search carefully.',
          ),
        );

        expect(captured?.url.toString(), 'https://example.com/v1/responses');
        expect(captured?.headers['Authorization'], 'Bearer openai-test');
        expect(captured?.headers['Content-Type'], contains('application/json'));
        expect(jsonDecode(captured!.body), {
          'model': 'custom-model',
          'input': [
            {'role': 'system', 'content': 'Search carefully.'},
            {'role': 'user', 'content': 'kelivo'},
          ],
          'tools': [
            {'type': 'web_search'},
          ],
          'store': false,
          'stream': false,
        });
        expect(result.answer, 'Kelivo is a Flutter chat client.');
        expect(result.items, hasLength(2));
        expect(result.items.first.title, 'Example A');
        expect(result.items.first.url, 'https://example.com/a');
        expect(result.items.last.title, 'https://example.com/b');
        expect(result.items.last.url, 'https://example.com/b');
      },
    );

    test('uses defaults and honors a zero result limit', () async {
      http.Request? captured;
      final service = OpenAIResponsesSearchService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': 'ok',
                      'annotations': [
                        {
                          'type': 'url_citation',
                          'url': 'https://example.com/a',
                          'title': 'Example A',
                        },
                      ],
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(resultSize: 0, timeout: 1000),
        serviceOptions: OpenAIResponsesOptions(
          id: 'openai-1',
          apiKey: 'openai-test',
          model: ' ',
          customUrl: ' ',
          systemPrompt: ' ',
        ),
      );

      expect(captured?.url.toString(), OpenAIResponsesOptions.defaultUrl);
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['model'], OpenAIResponsesOptions.defaultModel);
      expect((body['input'] as List).first, {
        'role': 'system',
        'content': OpenAIResponsesOptions.defaultSystemPrompt,
      });
      expect(result.answer, 'ok');
      expect(result.items, isEmpty);
    });

    test('throws before request when API key is empty', () async {
      var called = false;
      final service = OpenAIResponsesSearchService(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      expect(
        () => service.search(
          query: 'kelivo',
          commonOptions: const SearchCommonOptions(timeout: 1000),
          serviceOptions: OpenAIResponsesOptions(id: 'openai-1', apiKey: ''),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('OpenAI API key is required'),
          ),
        ),
      );
      expect(called, isFalse);
    });

    test('throws when the endpoint returns a non-success response', () async {
      final service = OpenAIResponsesSearchService(
        client: MockClient(
          (_) async => http.Response('secret upstream response', 429),
        ),
      );

      final future = service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(timeout: 1000),
        serviceOptions: OpenAIResponsesOptions(
          id: 'openai-1',
          apiKey: 'openai-test',
        ),
      );
      await expectLater(
        future,
        throwsA(
          isA<Exception>()
              .having(
                (error) => error.toString(),
                'message',
                contains('OpenAI Responses search failed'),
              )
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('secret upstream response')),
              ),
        ),
      );
    });

    test('rotates configured API keys across requests', () async {
      final authorizations = <String?>[];
      final service = OpenAIResponsesSearchService(
        client: MockClient((request) async {
          authorizations.add(request.headers['Authorization']);
          return http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {'type': 'output_text', 'text': 'ok'},
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      final options = OpenAIResponsesOptions(
        id: 'openai-rotation-test',
        apiKey: 'primary-key',
        extraApiKeys: const ['backup-key'],
      );

      for (var i = 0; i < 2; i++) {
        await service.search(
          query: 'kelivo',
          commonOptions: const SearchCommonOptions(timeout: 1000),
          serviceOptions: options,
        );
      }

      expect(authorizations, ['Bearer primary-key', 'Bearer backup-key']);
    });

    test('ignores malformed citation containers and unsafe URLs', () async {
      final service = OpenAIResponsesSearchService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': 'ok',
                      'annotations': {'unexpected': true},
                    },
                  ],
                },
              ],
              'citations': ['javascript:alert(1)'],
            }),
            200,
          ),
        ),
      );

      final result = await service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(timeout: 1000),
        serviceOptions: OpenAIResponsesOptions(
          id: 'openai-malformed-citations',
          apiKey: 'openai-test',
        ),
      );

      expect(result.answer, 'ok');
      expect(result.items, isEmpty);
    });
  });
}
