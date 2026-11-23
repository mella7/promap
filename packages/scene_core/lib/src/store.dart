import 'errors.dart';
import 'ops.dart';
import 'scene.dart';

/// One undoable step: the scene before and after, and what it was called.
class HistoryEntry {
  final Scene before;
  final Scene after;
  final String label;
  final List<SceneOp> ops;

  HistoryEntry(this.before, this.after, this.label, List<SceneOp> ops)
      : ops = List.unmodifiable(ops);
}

/// Holds the current scene and its undo history.
///
/// All edits go through [apply] or [applyAll], so every change can be undone
/// and anything that draws the scene can listen for updates.
class SceneStore {
  /// Oldest steps are dropped once the history holds this many.
  final int maxHistory;

  Scene _scene;
  final List<HistoryEntry> _undo = [];
  final List<HistoryEntry> _redo = [];
  final List<void Function(Scene)> _listeners = [];

  SceneStore(Scene scene, {this.maxHistory = 200}) : _scene = scene {
    if (maxHistory < 1) {
      throw ArgumentError('maxHistory must be at least 1');
    }
  }

  Scene get scene => _scene;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// What the next undo would reverse, or null.
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  /// What the next redo would bring back, or null.
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// Labels of the steps that can be undone, oldest first.
  List<String> get history => [for (final entry in _undo) entry.label];

  /// Applies one change as one undo step.
  void apply(SceneOp op) => applyAll([op], label: op.description);

  /// Applies several changes as a single undo step. If any of them fails with
  /// a [SceneError], none is applied and the error is rethrown.
  void applyAll(List<SceneOp> ops, {String? label}) {
    if (ops.isEmpty) return;
    var next = _scene;
    for (final op in ops) {
      next = op.apply(next);
    }
    final name = label ??
        (ops.length == 1 ? ops.first.description : '${ops.length} changes');
    _undo.add(HistoryEntry(_scene, next, name, ops));
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
    _redo.clear();
    _setScene(next);
  }

  /// Reverses the last step. Returns false when there is nothing to undo.
  bool undo() {
    if (_undo.isEmpty) return false;
    final entry = _undo.removeLast();
    _redo.add(entry);
    _setScene(entry.before);
    return true;
  }

  /// Brings back the last undone step. Returns false when there is none.
  bool redo() {
    if (_redo.isEmpty) return false;
    final entry = _redo.removeLast();
    _undo.add(entry);
    _setScene(entry.after);
    return true;
  }

  /// Swaps in a different scene, for example after loading a file. The undo
  /// history is cleared because it belongs to the old scene.
  void replaceScene(Scene scene) {
    _undo.clear();
    _redo.clear();
    _setScene(scene);
  }

  /// Calls [listener] with the new scene after every change.
  void addListener(void Function(Scene) listener) => _listeners.add(listener);

  void removeListener(void Function(Scene) listener) =>
      _listeners.remove(listener);

  void _setScene(Scene scene) {
    _scene = scene;
    for (final listener in List.of(_listeners)) {
      listener(scene);
    }
  }
}

/// Reads a list of operations from JSON, for example a batch sent by the
/// assistant. Throws [FormatException] if any entry is not an operation.
List<SceneOp> opsFromJson(Object? json) {
  if (json is! List) {
    throw const FormatException('Operations must be a list');
  }
  return [for (final entry in json) SceneOp.fromJson(entry)];
}

/// The message to show when reading or applying operations fails.
String describeFailure(Object error) {
  if (error is SceneError) return error.message;
  if (error is FormatException) return error.message;
  return error.toString();
}
