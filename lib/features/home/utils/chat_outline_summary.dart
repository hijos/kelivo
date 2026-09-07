import '../../../core/models/chat_message.dart';
import '../../../utils/utf16_safe_cut.dart';

/// Builds a deterministic, local-only message preview for the conversation
/// outline. No model call or full-history body hydration is required.
String buildChatOutlineMessageSummary(
  ChatMessage message, {
  required String generatingLabel,
  required String noTextLabel,
}) {
  if (message.isStreaming) return generatingLabel;
  final summary = message.content
      .replaceAll(
        RegExp(
          r'<(?:think|thought)>[\s\S]*?<\/(?:think|thought)>',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (summary.isEmpty) return noTextLabel;
  return truncateHeadUtf16Safe(summary, 200);
}
