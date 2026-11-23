"""Every op an assistant proposes goes through here before it reaches the
app. A rule-based assistant shouldn't get anything wrong, but a language
model can invent effects, surfaces or out-of-range values, so this is the
gate for both.

The assistant may only change how surfaces look: content, opacity,
visibility, name and label. Geometry stays with the scan.
"""

from typing import Any

from jsonschema import Draft202012Validator

from .catalog import Catalog, catalog, scene_schema
from .scene import SceneView

ALLOWED_OPS = {"set_content", "set_opacity", "set_visible", "rename_surface", "set_label"}


def _op_validator() -> Draft202012Validator:
    schema = scene_schema()
    return Draft202012Validator(
        {"$schema": schema["$schema"], "$defs": schema["$defs"], "$ref": "#/$defs/op"}
    )


def check_ops(
    ops: list[dict[str, Any]], scene: SceneView, cat: Catalog | None = None
) -> tuple[list[dict[str, Any]], list[str]]:
    """Returns the ops that are safe to apply (effect settings made valid)
    and a note for each one dropped."""
    cat = cat or catalog()
    validator = _op_validator()
    kept: list[dict[str, Any]] = []
    dropped: list[str] = []
    for op in ops:
        kind = op.get("op") if isinstance(op, dict) else None
        if kind not in ALLOWED_OPS:
            dropped.append(f"not allowed: {kind}")
            continue
        errors = list(validator.iter_errors(op))
        if errors:
            dropped.append(f"{kind}: {errors[0].message}")
            continue
        if scene.surface(op["surface"]) is None:
            dropped.append(f"{kind}: no surface {op['surface']}")
            continue
        if kind == "set_content" and op["content"]["type"] == "effect":
            effect = cat.effect(op["content"]["effect"])
            if effect is None:
                dropped.append(f"set_content: no effect {op['content']['effect']}")
                continue
            op = {
                **op,
                "content": {
                    "type": "effect",
                    "effect": effect.id,
                    "params": effect.resolve(op["content"].get("params", {})),
                },
            }
        if kind == "set_content" and op["content"]["type"] == "image":
            dropped.append("set_content: images aren't supported yet")
            continue
        kept.append(op)
    return kept, dropped
