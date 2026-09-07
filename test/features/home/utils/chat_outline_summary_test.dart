import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/home/utils/chat_outline_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the normalized beginning of the message body', () {
    final message = ChatMessage(
      id: 'user-1',
      role: 'user',
      conversationId: 'conversation',
      content: '  first line\n\n second\tline  ',
    );

    expect(
      buildChatOutlineMessageSummary(
        message,
        generatingLabel: 'generating',
        noTextLabel: 'empty',
      ),
      'first line second line',
    );
  });

  test('uses fixed streaming and empty placeholders', () {
    final streaming = ChatMessage(
      id: 'assistant-streaming',
      role: 'assistant',
      conversationId: 'conversation',
      content: 'partial body',
      isStreaming: true,
    );
    final empty = ChatMessage(
      id: 'assistant-empty',
      role: 'assistant',
      conversationId: 'conversation',
      content: '',
    );

    expect(
      buildChatOutlineMessageSummary(
        streaming,
        generatingLabel: 'generating…',
        noTextLabel: 'empty',
      ),
      'generating…',
    );
    expect(
      buildChatOutlineMessageSummary(
        empty,
        generatingLabel: 'generating…',
        noTextLabel: 'empty',
      ),
      'empty',
    );
  });

  test('limits summaries to 200 code units without splitting emoji', () {
    final prefix = List<String>.filled(199, 'a').join();
    final message = ChatMessage(
      id: 'assistant-long',
      role: 'assistant',
      conversationId: 'conversation',
      content: '$prefix😀tail',
    );

    final summary = buildChatOutlineMessageSummary(
      message,
      generatingLabel: 'generating',
      noTextLabel: 'empty',
    );
    expect(summary, prefix);
    expect(summary.length, lessThanOrEqualTo(200));
  });
}
