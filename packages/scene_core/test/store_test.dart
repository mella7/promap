import 'package:scene_core/scene_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late SceneStore store;
  late Scene original;

  setUp(() {
    original = sampleScene();
    store = SceneStore(original);
  });

  test('a fresh store has nothing to undo or redo', () {
    expect(store.scene, original);
    expect(store.canUndo, isFalse);
    expect(store.canRedo, isFalse);
    expect(store.undo(), isFalse);
    expect(store.redo(), isFalse);
    expect(store.undoLabel, isNull);
  });

  test('undo and redo step through changes', () {
    store.apply(const RenameSurface('s1', 'Back wall'));
    store.apply(const SetOpacity('s1', 0.4));

    expect(store.scene.surfaceById('s1')!.name, 'Back wall');
    expect(store.scene.surfaceById('s1')!.opacity, 0.4);
    expect(store.history, ['Rename to "Back wall"', 'Set opacity to 40%']);

    expect(store.undo(), isTrue);
    expect(store.scene.surfaceById('s1')!.opacity, 1.0);
    expect(store.scene.surfaceById('s1')!.name, 'Back wall');
    expect(store.redoLabel, 'Set opacity to 40%');

    expect(store.undo(), isTrue);
    expect(store.scene, original);
    expect(store.canUndo, isFalse);

    expect(store.redo(), isTrue);
    expect(store.redo(), isTrue);
    expect(store.scene.surfaceById('s1')!.opacity, 0.4);
    expect(store.canRedo, isFalse);
  });

  test('a new change after undo drops the redo list', () {
    store.apply(const SetVisible('s1', false));
    store.undo();
    expect(store.canRedo, isTrue);

    store.apply(const SetOpacity('s1', 0.2));
    expect(store.canRedo, isFalse);
    expect(store.scene.surfaceById('s1')!.visible, isTrue);
  });

  test('a batch is one undo step', () {
    store.applyAll(opsFromJson(fixtureJson('sample_ops.json')),
        label: 'Assistant edit');

    expect([for (final s in store.scene.surfaces) s.id], ['s1', 's4', 's3']);
    expect(store.history, ['Assistant edit']);

    store.undo();
    expect(store.scene, original);
  });

  test('a batch without a label gets a default one', () {
    store.applyAll(
        const [SetOpacity('s1', 0.5), SetVisible('s2', false)]);
    expect(store.undoLabel, '2 changes');
  });

  test('a failing batch changes nothing', () {
    expect(
        () => store.applyAll(const [
              RenameSurface('s1', 'Changed'),
              RemoveSurface('does-not-exist'),
            ]),
        throwsSceneError);

    expect(store.scene, original);
    expect(store.canUndo, isFalse);
  });

  test('an empty batch is ignored', () {
    store.applyAll(const []);
    expect(store.canUndo, isFalse);
  });

  test('history is capped at maxHistory', () {
    final small = SceneStore(original, maxHistory: 3);
    for (var i = 1; i <= 5; i++) {
      small.apply(SetOpacity('s1', i / 10));
    }
    expect(small.history.length, 3);

    while (small.undo()) {}
    // Only the last three steps could be undone, so the scene stops at the
    // state after the second change.
    expect(small.scene.surfaceById('s1')!.opacity, 0.2);
  });

  test('listeners hear about every change', () {
    final seen = <Scene>[];
    void listener(Scene scene) => seen.add(scene);
    store.addListener(listener);

    store.apply(const SetVisible('s1', false));
    store.undo();
    store.redo();
    store.replaceScene(original);
    expect(seen.length, 4);
    expect(seen.last, original);

    store.removeListener(listener);
    store.apply(const SetVisible('s1', false));
    expect(seen.length, 4);
  });

  test('loading another scene clears the history', () {
    store.apply(const SetVisible('s1', false));
    store.replaceScene(Scene(projectorWidth: 800, projectorHeight: 600));

    expect(store.scene.projectorWidth, 800);
    expect(store.canUndo, isFalse);
    expect(store.canRedo, isFalse);
  });

  test('describeFailure gives a readable message', () {
    try {
      store.apply(const RemoveSurface('ghost'));
      fail('should have thrown');
    } catch (error) {
      expect(describeFailure(error), 'There is no surface with id "ghost"');
    }
  });
}
