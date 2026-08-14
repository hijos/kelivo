import 'package:Kelivo/core/models/model_spec.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/reasoning/reasoning_dialects.dart';
import 'package:Kelivo/core/services/model_spec/model_spec_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final spec = ModelSpecResolver.instance.spec(
    ProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: '',
      enabled: true,
    ),
    'deepseek-v4-pro',
  );

  test('DeepSeek keeps its low, high, and max effort levels', () {
    expect(spec.reasoning.levels, [
      ReasoningLevel.low,
      ReasoningLevel.high,
      ReasoningLevel.max,
    ]);
    expect(spec.reasoning.canDisable, isTrue);
  });

  test('disabling DeepSeek thinking clears stale Chat Completions effort', () {
    final body = applyReasoning(
      <String, dynamic>{'reasoning_effort': 'high'},
      spec,
      const ReasoningRequest(ReasoningLevel.off),
      transport: ReasoningTransport.chatCompletions,
    );
    expect(body, {
      'thinking': {'type': 'disabled'},
    });
  });
}
