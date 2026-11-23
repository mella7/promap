# Step 3 (first half) - Scene core

The pure-logic part of step 3: scene graph, typed operations, undo and the
JSON format. The renderer and the drawing UI need the app and come later.

## Check it

```
cd packages/scene_core
dart pub get
dart analyze
dart test
```

## What the tests cover

- Loading and writing the sample scene, and defaults for optional fields
- Rejecting unreadable files and unsupported versions
- Every surface rule (corners, ids, names, opacity, colours, effect settings)
- Area, point-inside and "which surface is under this point"
- All 13 operations: JSON round trip, the result of a 14-step sequence, and
  each way an operation can be refused
- Undo, redo, batches as one step, failed batches, the history cap, listeners

## Open points

- The schema is checked against the fixtures with Python's jsonschema, not
  from Dart. A CI job should run that check once the backend exists.
- Scene files have no migration path yet. `version` is there so one can be
  added when the format first changes.
