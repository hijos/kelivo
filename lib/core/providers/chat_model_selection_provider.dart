import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/business_preferences.dart';
import '../models/chat_model_target.dart';

/// Persists ordered chat model combinations independently for each scope.
///
/// The ordered index is stored as one business preference row, separate from
/// chat timeline rows. Conversation ID remaps and deletions are explicit so
/// restore and lifecycle callers can keep the index consistent.
class ChatModelSelectionProvider extends ChangeNotifier {
  ChatModelSelectionProvider({required this.preferences}) {
    _ready = _load();
  }

  static const String storageKey = 'chat_model_selections_v1';
  static const int minimumTargets = 2;
  static const int maximumTargets = 5;
  static const String _fallbackAssistantKey = '__default__';

  final BusinessPreferences preferences;
  late final Future<void> _ready;
  MultiModelSelectionScope _scope = MultiModelSelectionScope.conversation;
  final Map<String, List<ChatModelTarget>> _assistantSelections = {};
  final Map<String, List<ChatModelTarget>> _conversationSelections = {};
  final Map<String, List<ChatModelTarget>> _nextMessageSelections = {};
  bool _loaded = false;

  Future<void> get ready => _ready;
  bool get isLoaded => _loaded;
  MultiModelSelectionScope get scope => _scope;

  Future<void> _load() async {
    await preferences.load();
    _loadFromPreferences();
  }

  void _loadFromPreferences() {
    final raw = preferences.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final json = decoded.cast<String, dynamic>();
          _scope = MultiModelSelectionScope.fromStorage(json['scope']);
          _decodeSelectionMap(json['assistants'], _assistantSelections);
          _decodeSelectionMap(json['conversations'], _conversationSelections);
          _decodeSelectionMap(json['nextMessages'], _nextMessageSelections);
        }
      } catch (_) {
        _assistantSelections.clear();
        _conversationSelections.clear();
        _nextMessageSelections.clear();
        _scope = MultiModelSelectionScope.conversation;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  void _decodeSelectionMap(
    Object? raw,
    Map<String, List<ChatModelTarget>> destination,
  ) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      if (entry.value is! List) continue;
      final targets = <ChatModelTarget>[];
      for (final value in entry.value as List) {
        if (value is! Map) continue;
        final target = ChatModelTarget.fromJson(value.cast<String, dynamic>());
        if (target.isValid && !targets.contains(target)) targets.add(target);
        if (targets.length == maximumTargets) break;
      }
      if (targets.length >= minimumTargets) {
        destination[entry.key.toString()] = List.unmodifiable(targets);
      }
    }
  }

  Future<void> setScope(MultiModelSelectionScope value) async {
    await _ensureLoaded();
    if (_scope == value) return;
    _scope = value;
    await _persist();
    notifyListeners();
  }

  List<ChatModelTarget> targetsForScope({
    MultiModelSelectionScope? scope,
    String? assistantId,
    String? conversationId,
  }) {
    if (!_loaded) return const <ChatModelTarget>[];
    final activeScope = scope ?? _scope;
    final targets = switch (activeScope) {
      MultiModelSelectionScope.assistant =>
        _assistantSelections[assistantId ?? _fallbackAssistantKey],
      MultiModelSelectionScope.conversation =>
        conversationId == null ? null : _conversationSelections[conversationId],
      MultiModelSelectionScope.nextMessage =>
        conversationId == null ? null : _nextMessageSelections[conversationId],
    };
    return List<ChatModelTarget>.unmodifiable(targets ?? const []);
  }

  List<ChatModelTarget> effectiveTargets({
    required ChatModelTarget fallback,
    String? assistantId,
    String? conversationId,
  }) {
    final configured = targetsForScope(
      assistantId: assistantId,
      conversationId: conversationId,
    );
    return configured.length >= minimumTargets
        ? configured
        : List<ChatModelTarget>.unmodifiable([fallback]);
  }

  Future<void> setTargets({
    required List<ChatModelTarget> targets,
    MultiModelSelectionScope? scope,
    String? assistantId,
    String? conversationId,
  }) async {
    await _ensureLoaded();
    final normalized = _normalizeRequired(targets);
    final activeScope = scope ?? _scope;
    switch (activeScope) {
      case MultiModelSelectionScope.assistant:
        _assistantSelections[assistantId ?? _fallbackAssistantKey] = normalized;
      case MultiModelSelectionScope.conversation:
        if (conversationId == null || conversationId.isEmpty) {
          throw ArgumentError.value(conversationId, 'conversationId');
        }
        _conversationSelections[conversationId] = normalized;
      case MultiModelSelectionScope.nextMessage:
        if (conversationId == null || conversationId.isEmpty) {
          throw ArgumentError.value(conversationId, 'conversationId');
        }
        _nextMessageSelections[conversationId] = normalized;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearActiveOverride({
    String? assistantId,
    String? conversationId,
  }) async {
    await clearTargets(
      scope: _scope,
      assistantId: assistantId,
      conversationId: conversationId,
    );
  }

  Future<void> clearTargets({
    required MultiModelSelectionScope scope,
    String? assistantId,
    String? conversationId,
  }) async {
    await _ensureLoaded();
    final removed = switch (scope) {
      MultiModelSelectionScope.assistant => _assistantSelections.remove(
        assistantId ?? _fallbackAssistantKey,
      ),
      MultiModelSelectionScope.conversation =>
        conversationId == null
            ? null
            : _conversationSelections.remove(conversationId),
      MultiModelSelectionScope.nextMessage =>
        conversationId == null
            ? null
            : _nextMessageSelections.remove(conversationId),
    };
    if (removed == null) return;
    await _persist();
    notifyListeners();
  }

  /// Consume a next-message override only after the generation batch exists.
  Future<List<ChatModelTarget>> consumeNextMessage(
    String conversationId,
  ) async {
    await _ensureLoaded();
    final removed = _nextMessageSelections.remove(conversationId);
    if (removed == null) return const [];
    await _persist();
    notifyListeners();
    return List.unmodifiable(removed);
  }

  Future<void> removeConversation(String conversationId) async {
    await _ensureLoaded();
    final removedConversation =
        _conversationSelections.remove(conversationId) != null;
    final removedNextMessage =
        _nextMessageSelections.remove(conversationId) != null;
    final changed = removedConversation || removedNextMessage;
    if (!changed) return;
    await _persist();
    notifyListeners();
  }

  Future<void> remapConversationIds(Map<String, String> remapping) async {
    await _ensureLoaded();
    var changed = false;
    for (final entry in remapping.entries) {
      changed =
          _remapKey(_conversationSelections, entry.key, entry.value) || changed;
      changed =
          _remapKey(_nextMessageSelections, entry.key, entry.value) || changed;
    }
    if (!changed) return;
    await _persist();
    notifyListeners();
  }

  Future<void> removeAssistant(String assistantId) async {
    await _ensureLoaded();
    if (_assistantSelections.remove(assistantId) == null) return;
    await _persist();
    notifyListeners();
  }

  Future<void> pruneTargets(
    bool Function(ChatModelTarget target) isAvailable,
  ) async {
    await _ensureLoaded();
    var changed = false;
    for (final map in <Map<String, List<ChatModelTarget>>>[
      _assistantSelections,
      _conversationSelections,
      _nextMessageSelections,
    ]) {
      for (final key in List<String>.of(map.keys)) {
        final filtered = map[key]!.where(isAvailable).toList(growable: false);
        if (filtered.length == map[key]!.length) continue;
        changed = true;
        if (filtered.length < minimumTargets) {
          map.remove(key);
        } else {
          map[key] = List.unmodifiable(filtered.take(maximumTargets));
        }
      }
    }
    if (!changed) return;
    await _persist();
    notifyListeners();
  }

  List<ChatModelTarget> _normalizeRequired(List<ChatModelTarget> targets) {
    final normalized = <ChatModelTarget>[];
    for (final target in targets) {
      if (!target.isValid || normalized.contains(target)) continue;
      normalized.add(target);
      if (normalized.length > maximumTargets) {
        throw ArgumentError.value(
          targets,
          'targets',
          'Select between $minimumTargets and $maximumTargets unique models.',
        );
      }
    }
    if (normalized.length < minimumTargets) {
      throw ArgumentError.value(
        targets,
        'targets',
        'Select between $minimumTargets and $maximumTargets unique models.',
      );
    }
    return List.unmodifiable(normalized);
  }

  bool _remapKey(
    Map<String, List<ChatModelTarget>> map,
    String source,
    String target,
  ) {
    if (source == target) return false;
    final value = map.remove(source);
    if (value == null) return false;
    map.putIfAbsent(target, () => value);
    return true;
  }

  Future<void> _persist() async {
    final payload = <String, dynamic>{
      'version': 1,
      'scope': _scope.name,
      'assistants': _encodeSelectionMap(_assistantSelections),
      'conversations': _encodeSelectionMap(_conversationSelections),
      'nextMessages': _encodeSelectionMap(_nextMessageSelections),
    };
    await preferences.setString(storageKey, jsonEncode(payload));
  }

  Future<void> _ensureLoaded() => _ready;

  Map<String, dynamic> _encodeSelectionMap(
    Map<String, List<ChatModelTarget>> source,
  ) => <String, dynamic>{
    for (final entry in source.entries)
      entry.key: [for (final target in entry.value) target.toJson()],
  };
}
