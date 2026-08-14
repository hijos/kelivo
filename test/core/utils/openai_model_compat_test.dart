import 'package:Kelivo/core/utils/openai_model_compat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepSeek reasoning effort compatibility', () {
    test('advertises none, xhigh, and max effort levels', () {
      const modelId = 'deepseek-v4-pro';

      expect(openAISupportsNoneReasoning(modelId), isTrue);
      expect(openAISupportsXhighReasoning(modelId), isTrue);
      expect(openAISupportsMaxReasoning(modelId), isTrue);
    });

    test('normalizes off to none and preserves max', () {
      const modelId = 'deepseek-v4-pro';

      expect(openAINormalizeReasoningEffort('off', modelId), 'none');
      expect(openAINormalizeReasoningEffort('max', modelId), 'max');
    });
  });
}
