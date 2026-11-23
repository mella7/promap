"""The effect library and themes, read from data/effects.json.

That file is a copy of schema/effects.json, which the app's effects
package is tested against, so both sides agree on effect ids, settings and
their ranges.
"""

import json
import re
from dataclasses import dataclass
from functools import cache
from importlib.resources import files
from typing import Any

HEX_COLOR = re.compile(r"^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")


@dataclass(frozen=True)
class Param:
    key: str
    label: str
    kind: str  # color, number or toggle
    default: Any
    min: float = 0.0
    max: float = 0.0

    def normalise(self, value: Any) -> Any:
        """Same rules as ParamSpec.normalise in the app: numbers clamped,
        wrong types and bad colours fall back to the default."""
        if self.kind == "color":
            if isinstance(value, str) and HEX_COLOR.match(value):
                return value.upper()
            return self.default
        if self.kind == "number":
            if isinstance(value, int | float) and not isinstance(value, bool):
                number = float(value)
                if number == number and abs(number) != float("inf"):
                    return min(max(number, self.min), self.max)
            return float(self.default)
        return value if isinstance(value, bool) else self.default


@dataclass(frozen=True)
class Effect:
    id: str
    name: str
    description: str
    params: tuple[Param, ...]

    def param(self, key: str) -> Param | None:
        return next((p for p in self.params if p.key == key), None)

    def resolve(self, given: dict[str, Any]) -> dict[str, Any]:
        """Every setting with a valid value; unknown keys are dropped."""
        return {p.key: p.normalise(given.get(p.key)) for p in self.params}


@dataclass(frozen=True)
class Theme:
    id: str
    name: str
    background: tuple[tuple[str, dict[str, Any]], ...]
    object: tuple[tuple[str, dict[str, Any]], ...]


@dataclass(frozen=True)
class Catalog:
    effects: tuple[Effect, ...]
    themes: tuple[Theme, ...]
    background_labels: frozenset[str]
    background_area_share: float

    def effect(self, effect_id: str) -> Effect | None:
        return next((e for e in self.effects if e.id == effect_id), None)

    def theme(self, theme_id: str) -> Theme | None:
        return next((t for t in self.themes if t.id == theme_id), None)


def _data(name: str) -> dict[str, Any]:
    return json.loads(files("promap_backend").joinpath("data", name).read_text())


@cache
def catalog() -> Catalog:
    raw = _data("effects.json")
    effects = tuple(
        Effect(
            id=e["id"],
            name=e["name"],
            description=e["description"],
            params=tuple(
                Param(
                    key=p["key"],
                    label=p["label"],
                    kind=p["kind"],
                    default=p["default"],
                    min=float(p.get("min", 0)),
                    max=float(p.get("max", 0)),
                )
                for p in e["params"]
            ),
        )
        for e in raw["effects"]
    )
    themes = tuple(
        Theme(
            id=t["id"],
            name=t["name"],
            background=tuple((c["effect"], c["params"]) for c in t["background"]),
            object=tuple((c["effect"], c["params"]) for c in t["object"]),
        )
        for t in raw["themes"]
    )
    return Catalog(
        effects,
        themes,
        frozenset(raw["backgroundLabels"]),
        float(raw["backgroundAreaShare"]),
    )


@cache
def scene_schema() -> dict[str, Any]:
    return _data("scene.schema.json")
