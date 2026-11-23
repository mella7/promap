"""What an assistant provides: a plan of scene ops for a typed request."""

from dataclasses import dataclass, field
from typing import Any, Protocol

from .scene import SceneView


@dataclass
class Plan:
    ops: list[dict[str, Any]]  # scene ops as JSON, see schema/scene.schema.json
    message: str  # shown to the user: what changed, or why nothing did
    dropped: list[str] = field(default_factory=list)  # ops the checker refused


class Assistant(Protocol):
    name: str

    def plan(self, scene: SceneView, prompt: str) -> Plan: ...
