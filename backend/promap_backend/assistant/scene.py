"""A read-only view of the scene the app sends, with what the assistant
needs: names, labels, roles and current content."""

from dataclasses import dataclass
from typing import Any

from jsonschema import Draft202012Validator

from .catalog import Catalog, catalog, scene_schema


class SceneError(ValueError):
    """The scene doesn't match schema/scene.schema.json."""


@dataclass(frozen=True)
class SurfaceView:
    id: str
    name: str
    label: str | None
    visible: bool
    opacity: float
    content: dict[str, Any]
    area: float

    @property
    def effect(self) -> str | None:
        return self.content.get("effect") if self.content.get("type") == "effect" else None


@dataclass(frozen=True)
class SceneView:
    width: int
    height: int
    surfaces: tuple[SurfaceView, ...]

    def surface(self, surface_id: str) -> SurfaceView | None:
        return next((s for s in self.surfaces if s.id == surface_id), None)

    def role(self, surface: SurfaceView, cat: Catalog | None = None) -> str:
        """background or object, the same rule as roleOf in the app."""
        cat = cat or catalog()
        label = (surface.label or "").lower()
        if label:
            return "background" if label in cat.background_labels else "object"
        share = surface.area / (self.width * self.height)
        return "background" if share > cat.background_area_share else "object"


def _area(vertices: list[list[float]]) -> float:
    total = 0.0
    for (x0, y0), (x1, y1) in zip(vertices, vertices[1:] + vertices[:1], strict=True):
        total += x0 * y1 - x1 * y0
    return abs(total) / 2


def read_scene(raw: Any) -> SceneView:
    errors = sorted(Draft202012Validator(scene_schema()).iter_errors(raw), key=str)
    if errors:
        raise SceneError(f"Scene doesn't match the schema: {errors[0].message}")
    return SceneView(
        width=raw["projector"]["width"],
        height=raw["projector"]["height"],
        surfaces=tuple(
            SurfaceView(
                id=s["id"],
                name=s["name"],
                label=s.get("label"),
                visible=s.get("visible", True),
                opacity=float(s.get("opacity", 1.0)),
                content=s.get("content", {"type": "none"}),
                area=_area(s["vertices"]),
            )
            for s in raw["surfaces"]
        ),
    )
