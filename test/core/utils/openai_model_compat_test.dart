import 'package:Kelivo/core/utils/openai_model_compat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepSeek reasoning effort compatibility', () {
    test('advertises the official low, high, and max effort levels', () {
      const modelId = 'deepseek-v4-pro';

      expect(openAISupportsNoneReasoning(modelId), isFalse);
      expect(openAISupportsXhighReasoning(modelId), isFalse);
      expect(openAISupportsMaxReasoning(modelId), isTrue);
    });

    test('keeps off out of Chat Completions and normalizes larger efforts', () {
      const modelId = 'deepseek-v4-pro';

      expect(openAINormalizeReasoningEffort('off', modelId), 'off');
      expect(openAINormalizeReasoningEffort('medium', modelId), 'high');
      expect(openAINormalizeReasoningEffort('xhigh', modelId), 'high');
      expect(openAINormalizeReasoningEffort('max', modelId), 'max');
    });
  });
}
