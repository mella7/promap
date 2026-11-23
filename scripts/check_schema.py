"""Checks schema/scene.schema.json against the scene_core test fixtures.

The Dart tests load the same fixtures, so this keeps the app and the backend
reading the same format. Run from the repo root:

    python scripts/check_schema.py
"""

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = json.loads((ROOT / "schema" / "scene.schema.json").read_text())
FIXTURES = ROOT / "packages" / "scene_core" / "test" / "fixtures"

Draft202012Validator.check_schema(SCHEMA)
scene_validator = Draft202012Validator(SCHEMA)
op_validator = Draft202012Validator(
    {"$schema": SCHEMA["$schema"], "$defs": SCHEMA["$defs"], "$ref": "#/$defs/op"}
)

failures = []

scene = json.loads((FIXTURES / "sample_scene.json").read_text())
for error in scene_validator.iter_errors(scene):
    failures.append(f"sample_scene.json: {error.message}")

ops = json.loads((FIXTURES / "sample_ops.json").read_text())
for index, op in enumerate(ops):
    for error in op_validator.iter_errors(op):
        failures.append(f"sample_ops.json[{index}] ({op.get('op')}): {error.message}")

# Things the schema must refuse.
bad_ops = [
    {"op": "set_opacity", "surface": "s1", "opacity": 2},
    {"op": "teleport", "surface": "s1"},
    {"op": "move_vertex", "surface": "s1", "index": 0, "position": [1, 2, 3]},
]
for op in bad_ops:
    if op_validator.is_valid(op):
        failures.append(f"schema accepted a bad operation: {op}")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"Schema OK: 1 scene and {len(ops)} operations valid, {len(bad_ops)} bad operations refused")
