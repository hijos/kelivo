import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class OpenAIResponsesSearchService
    extends SearchService<OpenAIResponsesOptions> {
  OpenAIResponsesSearchService({super.client});

  @override
  String get name => 'OpenAI Responses';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(
      l10n.searchProviderOpenAIResponsesDescription,
      style: const TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required OpenAIResponsesOptions serviceOptions,
  }) async {
    try {
      final apiKey = serviceOptions
          .effectiveApiKey(serviceOptions.apiKey)
          .trim();
      if (apiKey.isEmpty) {
        throw Exception('OpenAI API key is required');
      }

      final response = await withHttpClient(
        (client) => client
            .post(
              Uri.parse(serviceOptions.resolvedUrl),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': serviceOptions.resolvedModel,
                'input': [
                  {
                    'role': 'system',
                    'content': serviceOptions.resolvedSystemPrompt,
                  },
                  {'role': 'user', 'content': query},
                ],
                'tools': [
                  {'type': 'web_search'},
                ],
                'store': false,
                'stream': false,
              }),
            )
            .timeout(Duration(milliseconds: commonOptions.timeout)),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('API request failed (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Response root must be an object');
      }
      final data = Map<String, dynamic>.from(decoded);
      final output = _list(data['output']);
      final message = output.whereType<Map>().firstWhere(
        (item) => item['type'] == 'message' && item['role'] == 'assistant',
        orElse: () => const <String, dynamic>{},
      );
      final content = _list(message['content']);
      final textContent = content.whereType<Map>().firstWhere(
        (item) => item['type'] == 'output_text',
        orElse: () => const <String, dynamic>{},
      );

      final items = <SearchResultItem>[];
      _addCitationItems(
        items: items,
        citations: textContent['annotations'],
        maxItems: commonOptions.resultSize,
      );
      if (items.length < commonOptions.resultSize) {
        _addCitationItems(
          items: items,
          citations: data['citations'],
          maxItems: commonOptions.resultSize,
        );
      }

      return SearchResult(
        answer: textContent['text']?.toString(),
        items: items,
      );
    } catch (error) {
      throw Exception('OpenAI Responses search failed: $error');
    }
  }

  static List<Object?> _list(Object? value) =>
      value is List ? value.cast<Object?>() : const <Object?>[];

  static void _addCitationItems({
    required List<SearchResultItem> items,
    required Object? citations,
    required int maxItems,
  }) {
    if (maxItems <= 0 || citations is! List) return;
    final seenUrls = items.map((item) => item.url).toSet();
    for (final citation in citations) {
      final item = _citationItem(citation);
      if (item == null || !seenUrls.add(item.url)) continue;
      items.add(item);
      if (items.length >= maxItems) return;
    }
  }

  static SearchResultItem? _citationItem(Object? citation) {
    if (citation is String) {
      return _itemForUrl(citation, null);
    }

    if (citation is! Map || citation['type'] != 'url_citation') {
      return null;
    }
    return _itemForUrl(
      citation['url']?.toString(),
      citation['title']?.toString(),
    );
  }

  static SearchResultItem? _itemForUrl(String? rawUrl, String? rawTitle) {
    final url = rawUrl?.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (url.isEmpty ||
        uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final title = rawTitle?.trim();
    return SearchResultItem(
      title: title?.isNotEmpty == true ? title! : url,
      url: url,
      text: '',
    );
  }
}
