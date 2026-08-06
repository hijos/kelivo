import '../../providers/settings_provider.dart';
import 'builtin_tools.dart';

/// Resolves the request endpoint for OpenAI-compatible chat and Responses APIs.
Uri resolveOpenAICompatibleUrl(ProviderConfig config) {
  var rawBase = config.baseUrl.endsWith('/')
      ? config.baseUrl.substring(0, config.baseUrl.length - 1)
      : config.baseUrl;
  var baseUri = Uri.parse(rawBase);

  if (config.useResponseApi == true) {
    var normalizedPath = baseUri.path.replaceAll(RegExp(r'/$'), '');
    // Only the official DeepSeek endpoint moves Responses out of /v1.
    // Compatible relays may intentionally expose /v1/responses.
    if (baseUri.host.toLowerCase() == 'api.deepseek.com' &&
        normalizedPath == '/v1') {
      baseUri = baseUri.replace(path: '');
      rawBase = baseUri.toString().replaceAll(RegExp(r'/$'), '');
      normalizedPath = '';
    }
    if (BuiltInToolsHelper.isDashScopeProvider(config) &&
        normalizedPath != '/api/v2/apps/protocols/compatible-mode/v1') {
      return Uri.parse(
        '${baseUri.scheme}://${baseUri.authority}'
        '/api/v2/apps/protocols/compatible-mode/v1/responses',
      );
    }
    return Uri.parse('$rawBase/responses');
  }

  final path = config.chatPath ?? '/chat/completions';
  return Uri.parse('$rawBase$path');
}
