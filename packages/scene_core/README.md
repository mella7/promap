# scene_core

The app's data model: what surfaces exist, what each one shows, and every
way they can change. Plain Dart, no Flutter.

## The pieces

- **`Scene`** holds the projector size, the calibration file it belongs to
  and the surfaces in drawing order. A scene never changes; edits make a new
  one.
- **`Surface`** is a polygon in projector pixels with a name, an optional
  label ("window"), content, opacity and a visible flag.
- **`Content`** is one of: nothing, a colour, an image, or an effect with
  settings.
- **`SceneOp`** is one change. There are 13, and they are the only way to
  edit a scene.
- **`SceneStore`** holds the current scene, applies operations, keeps the
  undo history and tells listeners when something changed.

```dart
final store = SceneStore(Scene(projectorWidth: 1280, projectorHeight: 720));

store.apply(AddSurface(Surface(
  id: store.scene.nextSurfaceId(),
  name: 'Box top',
  vertices: const [Vec2(100, 100), Vec2(400, 120), Vec2(380, 300), Vec2(90, 280)],
)));
store.apply(SetContent('s1', ColorContent('#FF3300')));
store.apply(const NudgeVertex('s1', 0, -2, 1.5));

store.undo();                      // the nudge is gone
final text = store.scene.encode(); // JSON for a file
```

## Operations

| JSON name | What it does |
| --- | --- |
| `add_surface` | Add a surface, on top or at a given position |
| `remove_surface` | Delete a surface |
| `rename_surface` | Change the name the user sees |
| `set_label` | Set or clear what the surface is |
| `move_vertex` | Put one corner at an exact position |
| `nudge_vertex` | Shift one corner by a few pixels |
| `set_vertices` | Replace the whole outline |
| `translate_surface` | Shift a whole surface |
| `set_content` | Show a colour, image, effect or nothing |
| `set_opacity` | 0 to 1 |
| `set_visible` | Show or hide |
| `reorder_surface` | Change the drawing order |
| `set_calibration` | Point the scene at a calibration file |

Every operation reads from and writes to JSON, so the assistant can later
send a list of them and the app applies it with `store.applyAll(...)` as one
undo step. If any operation in a batch is not allowed, none is applied.

## Rules that are enforced

- Surface ids are unique and not empty; names are not empty.
- A surface has at least three corners and every coordinate is a real number.
- Opacity is between 0 and 1.
- Colours look like `#RRGGBB` or `#AARRGGBB`.
- Effect settings hold JSON values only.

Breaking a rule throws `SceneError` and changes nothing. Unreadable JSON
throws `FormatException`.

## Shared schema

`schema/scene.schema.json` at the repo root describes the same scene file and
the same operations for the backend. The two fixture files in
`test/fixtures/` are valid against that schema and are loaded by the Dart
tests, so the two sides are checked against the same examples.

## Not here yet

- Merging and splitting surfaces (step 4, when segmentation exists).
- Masks, feathering and blend modes (step 3, with the renderer).
