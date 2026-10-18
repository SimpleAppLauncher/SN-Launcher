import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'settings_store.dart';

/// A single thing to do.
@immutable
class TodoItem {
  const TodoItem({
    required this.id,
    required this.text,
    this.done = false,
  });

  final String id;
  final String text;
  final bool done;

  TodoItem copyWith({String? text, bool? done}) => TodoItem(
        id: id,
        text: text ?? this.text,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};

  /// Parses one stored entry.
  ///
  /// Returns null for anything unusable rather than throwing, because this
  /// reads a string that was written by an earlier version of the app and may
  /// have been hand-edited. One bad entry should cost one item, not the whole
  /// list.
  static TodoItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    if (id is! String || id.isEmpty) return null;
    if (text is! String || text.trim().isEmpty) return null;
    return TodoItem(id: id, text: text, done: raw['done'] == true);
  }
}

/// A to-do list that survives a restart.
///
/// Deliberately not a plugin and not a database. A list of short strings is
/// exactly what [SettingsStore] is for, and this project's Android build is
/// fragile enough without another dependency.
///
/// **Fail-closed on read.** If the stored string is not valid JSON, or is not a
/// list, the list starts empty rather than guessing. A half-parsed list is
/// worse than an empty one, and an empty one is honest: the user can see that
/// nothing is on it.
class TodoService extends ChangeNotifier {
  TodoService(this._settings);

  final SettingsStore _settings;

  List<TodoItem> _items = const [];
  bool _loaded = false;

  /// The items, in the order they were added. Done items sort to the bottom
  /// so the list you are working through stays at the top.
  List<TodoItem> get items {
    final pending = _items.where((i) => !i.done).toList();
    final done = _items.where((i) => i.done).toList();
    return [...pending, ...done];
  }

  /// How many are still outstanding. This is the number worth showing.
  int get openCount => _items.where((i) => !i.done).length;

  bool get isEmpty => _items.isEmpty;

  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    // Load the store first. Reading a key off a store that has not loaded yet
    // returns null, which is indistinguishable from "the user has never had a
    // to-do list" — so a list saved yesterday would silently come back empty.
    // Depending on the caller to have loaded it first is the kind of coupling
    // that only shows up in a test.
    await _settings.load();
    final raw = _settings.get(SettingKeys.todo);
    if (raw == null || raw.isEmpty) {
      _items = const [];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _items = const [];
        return;
      }
      _items = [
        for (final entry in decoded)
          if (TodoItem.fromJson(entry) != null) TodoItem.fromJson(entry)!,
      ];
    } catch (_) {
      _items = const [];
    }
    notifyListeners();
  }

  /// Adds an item. Blank text is ignored rather than added as an empty row.
  Future<void> add(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final item = TodoItem(
      // A millisecond timestamp is unique enough for a hand-curated list and
      // keeps the order stable without a counter that could desynchronise.
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: trimmed,
    );
    _items = [..._items, item];
    notifyListeners();
    await _persist();
  }

  Future<void> toggle(String id) async {
    var changed = false;
    final next = <TodoItem>[];
    for (final i in _items) {
      if (i.id == id) {
        changed = true;
        next.add(i.copyWith(done: !i.done));
      } else {
        next.add(i);
      }
    }
    if (!changed) return;
    _items = next;
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    final before = _items.length;
    _items = _items.where((i) => i.id != id).toList();
    if (_items.length == before) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await _settings.put(
      SettingKeys.todo,
      jsonEncode([for (final i in _items) i.toJson()]),
    );
  }
}
