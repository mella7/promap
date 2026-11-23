"""The assistant: typed requests in, checked scene ops out.

Every assistant's ops go through check.check_ops, so the app only ever
gets ops it can apply: known surfaces, known effects, valid settings, and
only look-and-feel changes (no geometry).
"""

from .base import Assistant, Plan
from .check import check_ops
from .rules import RuleAssistant
from .scene import SceneError, SceneView, read_scene

_ASSISTANTS = {"rules": RuleAssistant}


def load_assistant(name: str) -> Assistant:
    try:
        return _ASSISTANTS[name]()
    except KeyError:
        raise ValueError(f"Unknown assistant '{name}', choose from {sorted(_ASSISTANTS)}") from None


def run(assistant: Assistant, raw_scene: object, prompt: str) -> Plan:
    """Reads the scene, asks the assistant, checks its ops."""
    scene = read_scene(raw_scene)
    plan = assistant.plan(scene, prompt)
    ops, dropped = check_ops(plan.ops, scene)
    return Plan(ops, plan.message, dropped)


__all__ = [
    "Assistant",
    "Plan",
    "RuleAssistant",
    "SceneError",
    "SceneView",
    "check_ops",
    "load_assistant",
    "read_scene",
    "run",
]
