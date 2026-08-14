import '../../../core/models/chat_message.dart';
import '../../../core/database/generation_run.dart';

/// Immutable, precomputed input for one logical timeline slot.
///
/// Renderer code must not scan the full message list or sort revisions while
/// building an individual row.
final class MessageRenderModel {
  const MessageRenderModel({
    required this.slotId,
    required this.message,
    required this.versions,
    required this.availableVersions,
    required this.versionCount,
    required this.selectedVersionIndex,
    required this.selectedVersion,
    required this.previousVersion,
    required this.nextVersion,
    required this.hasMultipleModelTargets,
    required this.targetGenerationStates,
    required this.showContextDivider,
    required this.isLatestCompleteAssistant,
  });

  final String slotId;
  final ChatMessage message;
  final List<ChatMessage> versions;
  final List<int> availableVersions;
  final int versionCount;
  final int selectedVersionIndex;

  /// Persisted version values are identifiers, not list indexes. These fields
  /// keep navigation correct after a sibling revision is deleted and versions
  /// become sparse.
  final int selectedVersion;
  final int? previousVersion;
  final int? nextVersion;

  /// Whether this slot contains answers from at least two provider/model
  /// targets. Such slots use model chips instead of the legacy branch arrows.
  final bool hasMultipleModelTargets;
  final Map<String, GenerationRunState> targetGenerationStates;
  final bool showContextDivider;
  final bool isLatestCompleteAssistant;
}

final class MessageRenderModelProjector {
  const MessageRenderModelProjector._();

  static List<MessageRenderModel> project({
    required List<ChatMessage> messages,
    required Map<String, List<ChatMessage>> byGroup,
    required Map<String, int> versionSelections,
    Map<String, int> versionCounts = const <String, int>{},
    Map<String, GenerationRunState> generationStates =
        const <String, GenerationRunState>{},
    required int contextDividerIndex,
  }) {
    var latestCompleteAssistantIndex = -1;
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.role == 'assistant' && !message.isStreaming) {
        latestCompleteAssistantIndex = index;
        break;
      }
    }

    return List<MessageRenderModel>.unmodifiable([
      for (final (index, message) in messages.indexed)
        _projectSlot(
          index: index,
          message: message,
          versions: byGroup[message.groupId ?? message.id],
          selectedVersion: versionSelections[message.groupId ?? message.id],
          authoritativeVersionCount:
              versionCounts[message.groupId ?? message.id],
          generationStates: generationStates,
          contextDividerIndex: contextDividerIndex,
          latestCompleteAssistantIndex: latestCompleteAssistantIndex,
        ),
    ]);
  }

  static MessageRenderModel _projectSlot({
    required int index,
    required ChatMessage message,
    required List<ChatMessage>? versions,
    required int? selectedVersion,
    required int? authoritativeVersionCount,
    required Map<String, GenerationRunState> generationStates,
    required int contextDividerIndex,
    required int latestCompleteAssistantIndex,
  }) {
    final sortedVersions = List<ChatMessage>.of(
      versions ?? const <ChatMessage>[],
    )..sort((left, right) => left.version.compareTo(right.version));
    final loadedVersionCount = sortedVersions.isEmpty
        ? 1
        : sortedVersions.length;
    final versionCount = (authoritativeVersionCount ?? loadedVersionCount)
        .clamp(loadedVersionCount, 1 << 31)
        .toInt();
    final candidates = sortedVersions.isEmpty
        ? <ChatMessage>[message]
        : sortedVersions;
    final availableVersions = candidates
        .map((candidate) => candidate.version)
        .toList(growable: false);
    final requestedVersion = selectedVersion ?? message.version;
    var selectedIndex = candidates.indexWhere(
      (candidate) => candidate.version == requestedVersion,
    );
    if (selectedIndex < 0) {
      selectedIndex = candidates.indexWhere(
        (candidate) => candidate.id == message.id,
      );
    }
    if (selectedIndex < 0) selectedIndex = 0;

    final actualSelectedVersion = candidates[selectedIndex].version;
    final modelTargets = <String>{
      for (final candidate in candidates)
        if (candidate.role == 'assistant' &&
            candidate.providerId != null &&
            candidate.modelId != null)
          '${candidate.providerId}\u0000${candidate.modelId}',
    };
    return MessageRenderModel(
      slotId: message.groupId ?? message.id,
      message: message,
      versions: List<ChatMessage>.unmodifiable(sortedVersions),
      availableVersions: List<int>.unmodifiable(availableVersions),
      versionCount: versionCount,
      selectedVersionIndex: selectedIndex,
      selectedVersion: actualSelectedVersion,
      previousVersion: selectedIndex > 0
          ? candidates[selectedIndex - 1].version
          : null,
      nextVersion: selectedIndex + 1 < candidates.length
          ? candidates[selectedIndex + 1].version
          : null,
      hasMultipleModelTargets: modelTargets.length >= 2,
      targetGenerationStates: Map<String, GenerationRunState>.unmodifiable({
        for (final candidate in candidates)
          if (generationStates[candidate.id] case final state?)
            candidate.id: state,
      }),
      showContextDivider:
          contextDividerIndex >= 0 && index == contextDividerIndex,
      isLatestCompleteAssistant: index == latestCompleteAssistantIndex,
    );
  }
}
