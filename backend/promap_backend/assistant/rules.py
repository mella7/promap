"""An assistant without a language model: it understands short requests
built from surfaces, effects, colours, speed and brightness words.

    make the walls sparkle and the box pulse red
    starry theme
    walls blue scanlines, slower
    hide the ceiling
    dim everything to 40%

It's free, instant and works offline, and it's the baseline a language
model has to beat. Anything it doesn't understand gets a short hint back
instead of a guess.
"""

import re
from dataclasses import dataclass, field
from typing import Any

from .base import Plan
from .catalog import Catalog, Effect, catalog
from .scene import SceneView

COLORS = {
    "warm white": "#FFE2B8",
    "cool white": "#DDEBFF",
    "white": "#FFFFFF",
    "red": "#FF2A2A",
    "orange": "#FF7A1A",
    "amber": "#FFB000",
    "gold": "#FFC83D",
    "yellow": "#FFE600",
    "lime": "#A6FF00",
    "green": "#2EE05B",
    "teal": "#14C7B5",
    "cyan": "#00E5FF",
    "blue": "#2E6BFF",
    "navy": "#1A237E",
    "purple": "#8A2BFF",
    "violet": "#8A2BFF",
    "magenta": "#FF2BD6",
    "pink": "#FF5FA2",
}

# Effect ids and the words that ask for them. Order matters: first match wins.
EFFECT_WORDS = [
    ("edge_trace", r"\b(trace|tracing|chase|chasing|runs? around|running light)\b"),
    ("neon_outline", r"\b(neon|outlines?|outlined|glow(ing)? edges?|edges? glow)\b"),
    ("sparkles", r"\b(sparkles?|sparkling|stars|twinkles?|twinkling|glitter|glittering)\b"),
    ("scanlines", r"\b(scan ?lines?|stripes?|striped|lines)\b"),
    ("color_flood", r"\b(flood|floods|fills?|filling|wash|washes)\b"),
    ("pulse", r"\b(pulse|pulses|pulsing|breathes?|breathing|fades?|throb|throbbing|beat)\b"),
]

THEME_WORDS = [
    ("neon_night", r"\b(neon night|cyberpunk|synthwave)\b"),
    ("warm_glow", r"\b(warm glow|cosy|cozy|warm theme|fireplace)\b"),
    ("starry", r"\b(starry|night sky|galaxy|space theme)\b"),
]

ALL_WORDS = r"\b(everything|every surface|all surfaces|all of it|whole (room|scene|thing)|all)\b"
BACKGROUND_WORDS = r"\b(background|backdrop|room)\b"
OBJECT_WORDS = r"\b(objects?|things|stuff|furniture|items?|boxe?s?)\b"
LABEL_WORDS = {
    "wall": r"\bwalls?\b",
    "ceiling": r"\bceilings?\b",
    "floor": r"\bfloors?\b",
}
PRONOUNS = r"\b(it|them|those|these|that|this)\b"

HIDE = r"\b(hide|turn (it |them )?off|switch (it |them )?off|black ?out|blank)\b"
SHOW = r"\b(show|unhide|turn (it |them )?on|switch (it |them )?on|bring (it |them )?back)\b"
CLEAR = r"\b(clear|no effects?|remove (the )?effects?|nothing)\b"
FASTER = r"\b(faster|fast|quick|quicker|rapid|speed (it |them )?up)\b"
SLOWER = r"\b(slower|slow|calm|calmer|gentle|gently|relaxed|slow (it |them )?down)\b"
DIMMER = r"\b(dim|dimmer|darker|softer|fainter|subtle)\b"
BRIGHTER = r"\b(brighter|full brightness|bright)\b"


@dataclass
class Clause:
    text: str
    targets: list[str] | None = None  # surface ids, None if the clause names none
    effect: str | None = None
    theme: str | None = None
    color: str | None = None
    speed_factor: float | None = None
    speed: float | None = None
    opacity: float | None = None
    opacity_factor: float | None = None
    visible: bool | None = None
    clear: bool = False

    @property
    def does_something(self) -> bool:
        return (
            any(
                v is not None
                for v in (
                    self.effect,
                    self.theme,
                    self.color,
                    self.speed_factor,
                    self.speed,
                    self.opacity,
                    self.opacity_factor,
                    self.visible,
                )
            )
            or self.clear
        )


@dataclass
class _State:
    """The scene as the ops so far would leave it."""

    content: dict[str, dict[str, Any]]
    opacity: dict[str, float]
    visible: dict[str, bool]
    ops: list[dict[str, Any]] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def _clauses(prompt: str) -> list[str]:
    text = prompt.lower().strip()
    parts = re.split(r"\s*(?:[,;.!]|\band then\b|\bthen\b|\band\b|\bplus\b)\s*", text)
    return [p for p in parts if p]


def _find_targets(text: str, scene: SceneView) -> tuple[list[str] | None, str]:
    """Surface ids the text names, and the text with those words removed."""
    ids: list[str] = []
    rest = text
    # Names first, longest first, so "wall 2" beats "wall".
    for surface in sorted(scene.surfaces, key=lambda s: len(s.name), reverse=True):
        pattern = r"\b" + re.escape(surface.name.lower()) + r"\b"
        if re.search(pattern, rest):
            ids.append(surface.id)
            rest = re.sub(pattern, " ", rest)
    if re.search(ALL_WORDS, rest):
        return [s.id for s in scene.surfaces], re.sub(ALL_WORDS, " ", rest)
    for label, pattern in LABEL_WORDS.items():
        if re.search(pattern, rest):
            matched = [s.id for s in scene.surfaces if (s.label or "").lower() == label]
            if not matched and label == "wall":
                matched = [s.id for s in scene.surfaces if scene.role(s) == "background"]
            ids += [i for i in matched if i not in ids]
            rest = re.sub(pattern, " ", rest)
    if re.search(BACKGROUND_WORDS, rest):
        ids += [s.id for s in scene.surfaces if scene.role(s) == "background" and s.id not in ids]
        rest = re.sub(BACKGROUND_WORDS, " ", rest)
    if re.search(OBJECT_WORDS, rest):
        ids += [s.id for s in scene.surfaces if scene.role(s) == "object" and s.id not in ids]
        rest = re.sub(OBJECT_WORDS, " ", rest)
    if ids:
        return ids, rest
    if re.search(PRONOUNS, rest):
        return [], rest  # "it": the caller fills in the last targets
    return None, rest


def parse(prompt: str, scene: SceneView, cat: Catalog) -> list[Clause]:
    clauses = []
    for text in _clauses(prompt):
        targets, rest = _find_targets(text, scene)
        clause = Clause(text=text, targets=targets)
        for theme_id, pattern in THEME_WORDS:
            if re.search(pattern, rest):
                clause.theme = theme_id
                rest = re.sub(pattern, " ", rest)
                break
        hex_match = re.search(r"#[0-9a-f]{6}\b", rest)
        if hex_match:
            clause.color = hex_match.group(0).upper()
        else:
            for name, value in COLORS.items():
                if re.search(r"\b" + name + r"\b", rest):
                    clause.color = value
                    rest = re.sub(r"\b" + name + r"\b", " ", rest)
                    break
        for effect_id, pattern in EFFECT_WORDS:
            if cat.effect(effect_id) and re.search(pattern, rest):
                clause.effect = effect_id
                break
        very = 1.5 if re.search(r"\b(very|much|really|super)\b", rest) else 1.0
        if re.search(FASTER, rest):
            clause.speed_factor = 2.0 * very
        elif re.search(SLOWER, rest):
            clause.speed_factor = 0.5 / very
        speed = re.search(r"\bspeed (?:of |to )?(\d+(?:\.\d+)?)\b", rest)
        if speed:
            clause.speed = float(speed.group(1))
        percent = re.search(r"\b(\d{1,3})\s*%", rest)
        if percent:
            clause.opacity = min(int(percent.group(1)), 100) / 100
        elif re.search(DIMMER, rest):
            clause.opacity_factor = 0.5
        elif re.search(BRIGHTER, rest):
            clause.opacity = 1.0
        if re.search(HIDE, rest):
            clause.visible = False
        elif re.search(SHOW, rest):
            clause.visible = True
        if re.search(CLEAR, rest):
            clause.clear = True
        clauses.append(clause)
    return clauses


def _set_content(state: _State, surface_id: str, content: dict[str, Any]) -> None:
    state.content[surface_id] = content
    state.ops = [
        op for op in state.ops if not (op["op"] == "set_content" and op["surface"] == surface_id)
    ]
    state.ops.append({"op": "set_content", "surface": surface_id, "content": content})


def _effect_content(
    effect: Effect, current: dict[str, Any], clause: Clause, keep_settings: bool
) -> dict[str, Any]:
    params = dict(current.get("params", {})) if keep_settings else {}
    if clause.color:
        params["color"] = clause.color
    speed_param = effect.param("speed")
    if speed_param is not None:
        speed = float(params.get("speed", speed_param.default))
        if clause.speed is not None:
            params["speed"] = clause.speed
        elif clause.speed_factor is not None:
            params["speed"] = speed * clause.speed_factor
    return {"type": "effect", "effect": effect.id, "params": effect.resolve(params)}


def _names(ids: list[str], scene: SceneView) -> str:
    names = [s.name for s in scene.surfaces if s.id in ids]
    if len(names) > 3:
        return f"{len(names)} surfaces"
    return ", ".join(names)


def _apply_theme(state: _State, theme_id: str, ids: list[str], scene: SceneView, cat: Catalog):
    theme = cat.theme(theme_id)
    if theme is None:
        return
    used = {"background": 0, "object": 0}
    for surface in scene.surfaces:
        if surface.id not in ids or not state.visible[surface.id]:
            continue
        role = scene.role(surface, cat)
        choices = theme.background if role == "background" else theme.object
        if not choices:
            continue
        effect_id, params = choices[used[role] % len(choices)]
        used[role] += 1
        effect = cat.effect(effect_id)
        if effect is not None:
            _set_content(
                state,
                surface.id,
                {"type": "effect", "effect": effect.id, "params": effect.resolve(params)},
            )
    state.notes.append(f"{theme.name} theme on {_names(ids, scene)}")


def _apply(state: _State, clause: Clause, ids: list[str], scene: SceneView, cat: Catalog):
    what: list[str] = []
    if clause.theme:
        _apply_theme(state, clause.theme, ids, scene, cat)
    if clause.clear:
        for surface_id in ids:
            _set_content(state, surface_id, {"type": "none"})
        what.append("cleared")
    elif clause.effect:
        effect = cat.effect(clause.effect)
        assert effect is not None  # noqa: S101 - parse only picks known effects
        for surface_id in ids:
            current = state.content[surface_id]
            same = current.get("type") == "effect" and current.get("effect") == effect.id
            _set_content(state, surface_id, _effect_content(effect, current, clause, same))
        what.append(effect.name.lower())
    elif clause.color or clause.speed_factor is not None or clause.speed is not None:
        changed_speed = False
        for surface_id in ids:
            current = state.content[surface_id]
            effect = (
                cat.effect(current.get("effect", "")) if current.get("type") == "effect" else None
            )
            if effect is not None:
                _set_content(state, surface_id, _effect_content(effect, current, clause, True))
                changed_speed = changed_speed or effect.param("speed") is not None
            elif clause.color:
                _set_content(state, surface_id, {"type": "color", "color": clause.color})
        if clause.speed_factor is not None or clause.speed is not None:
            what.append("faster" if (clause.speed_factor or 1) > 1 else "slower")
            if not changed_speed:
                state.notes.append(f"{_names(ids, scene)} has no effect to change the speed of")
    if clause.color:
        name = next((n for n, v in COLORS.items() if v == clause.color), clause.color)
        what.append(name)
    if clause.opacity is not None or clause.opacity_factor is not None:
        for surface_id in ids:
            value = clause.opacity
            if value is None:
                value = max(0.1, state.opacity[surface_id] * (clause.opacity_factor or 1))
            state.opacity[surface_id] = round(value, 3)
            state.ops.append(
                {"op": "set_opacity", "surface": surface_id, "opacity": round(value, 3)}
            )
        what.append(f"brightness {round(state.opacity[ids[0]] * 100)}%" if ids else "brightness")
    if clause.visible is not None:
        for surface_id in ids:
            state.visible[surface_id] = clause.visible
            state.ops.append(
                {"op": "set_visible", "surface": surface_id, "visible": clause.visible}
            )
        what.append("shown" if clause.visible else "hidden")
    if what:
        state.notes.append(f"{_names(ids, scene)}: {', '.join(what)}")


HINT = (
    "I didn't catch what to change. Try something like 'make the walls sparkle', "
    "'pulse the box red', 'starry theme' or 'hide the ceiling'."
)


class RuleAssistant:
    name = "rules"

    def __init__(self, cat: Catalog | None = None):
        self.catalog = cat or catalog()

    def plan(self, scene: SceneView, prompt: str) -> Plan:
        if not scene.surfaces:
            return Plan([], "There are no surfaces yet. Scan and find surfaces first.")
        state = _State(
            content={s.id: dict(s.content) for s in scene.surfaces},
            opacity={s.id: s.opacity for s in scene.surfaces},
            visible={s.id: s.visible for s in scene.surfaces},
        )
        everything = [s.id for s in scene.surfaces]
        last: list[str] | None = None
        pending: list[str] = []
        for clause in parse(prompt, scene, self.catalog):
            if not clause.does_something:
                # "the walls and the ceiling sparkle": hold the walls for the
                # clause that says what to do.
                pending += [i for i in (clause.targets or []) if i not in pending]
                continue
            if clause.targets:
                ids = pending + [i for i in clause.targets if i not in pending]
            elif pending:
                ids = pending
            else:
                ids = last or everything
            pending = []
            _apply(state, clause, ids, scene, self.catalog)
            last = ids
        if not state.ops:
            return Plan([], ". ".join(state.notes) + "." if state.notes else HINT)
        return Plan(state.ops, ". ".join(state.notes) + ".")
