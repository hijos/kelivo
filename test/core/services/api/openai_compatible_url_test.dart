import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/providers/model_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/openai_compatible_url.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderConfig _config(String baseUrl, {bool useResponseApi = true}) {
  return ProviderConfig(
    id: 'DeepSeekUrlTest',
    enabled: true,
    name: 'DeepSeekUrlTest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
    useResponseApi: useResponseApi,
  );
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
  group('resolveOpenAICompatibleUrl', () {
    test('uses the root Responses endpoint for official DeepSeek', () {
      expect(
        resolveOpenAICompatibleUrl(
          _config('https://api.deepseek.com/v1'),
        ).toString(),
        'https://api.deepseek.com/responses',
      );
    });

    test('keeps an explicit v1 path for third-party relays', () {
      expect(
        resolveOpenAICompatibleUrl(
          _config('https://relay.example/v1'),
        ).toString(),
        'https://relay.example/v1/responses',
      );
    });

    test('uses the DashScope compatible-mode Responses endpoint', () {
      expect(
        resolveOpenAICompatibleUrl(
          _config('https://dashscope.aliyuncs.com/compatible-mode/v1'),
        ).toString(),
        'https://dashscope.aliyuncs.com/api/v2/apps/protocols/compatible-mode/v1/responses',
      );
    });

    test('keeps Chat Completions path behavior unchanged', () {
      expect(
        resolveOpenAICompatibleUrl(
          _config(
            'https://relay.example/v1',
            useResponseApi: false,
          ).copyWith(chatPath: '/chat/completions'),
        ).toString(),
        'https://relay.example/v1/chat/completions',
      );
    });

    test(
      'ProviderManager connection test shares official DeepSeek URL',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final paths = <String>[];
        final bodies = <Map<String, dynamic>>[];
        server.listen((request) async {
          paths.add(request.uri.path);
          bodies.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
          await request.response.close();
        });

        await HttpOverrides.runZoned(
          () => ProviderManager.testConnection(
            _config('http://api.deepseek.com/v1'),
            'deepseek-v4-flash',
          ),
          createHttpClient: (context) =>
              _ProxyHttpOverrides(server.port).createHttpClient(context),
        );

        expect(paths, ['/responses']);
        expect(bodies.single['model'], 'deepseek-v4-flash');
      },
    );
  });
}
