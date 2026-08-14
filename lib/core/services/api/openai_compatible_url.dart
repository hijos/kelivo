import '../../providers/settings_provider.dart';
import 'builtin_tools.dart';

/// Resolves the request endpoint for OpenAI-compatible Chat Completions and
/// Responses APIs while preserving vendor-specific endpoint conventions.
Uri resolveOpenAICompatibleUrl(ProviderConfig config) {
  var rawBase = config.baseUrl.endsWith('/')
      ? config.baseUrl.substring(0, config.baseUrl.length - 1)
      : config.baseUrl;
  var baseUri = Uri.parse(rawBase);

  if (config.useResponseApi == true) {
    var normalizedPath = baseUri.path.replaceAll(RegExp(r'/$'), '');
    // DeepSeek's official Responses endpoint is rooted at /responses even
    // though its common compatibility base URL is normally configured as /v1.
    // Third-party relays keep their explicitly configured /v1 path.
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
