# effects

The effect library: which effects exist, what settings each one has, and
themes that hand effects out to every surface in one go. Plain Dart, no
Flutter. The drawing itself lives in the app (`app/lib/ui/effect_painter.dart`).

## Effects

| Id | Name | Settings |
| --- | --- | --- |
| `neon_outline` | Neon outline | colour, speed, line width |
| `color_flood` | Colour flood | colour, speed, fill upwards or sideways |
| `pulse` | Pulse | colour, speed, strength |
| `scanlines` | Scanlines | colour, speed, spacing |
| `sparkles` | Sparkles | colour, speed, density |
| `edge_trace` | Edge trace | colour, speed, tail length |

An effect is stored in the scene as `EffectContent(id, params)`. Settings go
through `EffectSpec.resolve`, which fills in defaults, clamps numbers to
their range and drops anything it doesn't know, so a scene file or the AI
assistant can't push an effect into a broken state.

Every effect reads the surface it's on (outline, size, its id for random
seeds), so the same effect fits a box lid and a whole wall.

## Themes

A theme lists effects per role. `roleOf` decides the role: the label first
("wall", "floor" and "ceiling" are background, any other label is an object),
then size (more than 20% of the projector image is background).

| Theme | Background | Objects |
| --- | --- | --- |
| Neon night | blue and purple scanlines | neon outline, edge trace |
| Warm glow | slow amber pulse | colour flood, pulse |
| Starry | sparkles | thin white outline |

`themeOps(scene, theme)` returns one `SetContent` per visible surface. Apply
them with `store.applyAll` so the whole theme is one undo step. Surfaces of
the same role take the theme's choices in turn.

## Adding an effect

1. Add an `EffectSpec` to `effectLibrary` in `lib/src/library.dart`.
2. Draw it in `app/lib/ui/effect_painter.dart`.
3. The tests check that its defaults are valid and that it survives JSON.

Ids are stored in scene files, so never rename one that's in use.

## Tests

```
dart pub get
dart test
```
