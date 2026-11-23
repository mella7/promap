"""The assistant: catalog, rule parser, the op check and the endpoint."""

import json

import pytest
from fastapi.testclient import TestClient

from promap_backend.assistant import RuleAssistant, check_ops, read_scene, run
from promap_backend.assistant.catalog import catalog
from promap_backend.assistant.scene import SceneError
from promap_backend.config import Settings
from promap_backend.main import create_app

SCENE = {
    "version": 1,
    "projector": {"width": 1280, "height": 720},
    "surfaces": [
        {"id": "s1", "name": "Wall", "label": "wall", "vertices": [[0, 0], [700, 0], [700, 720]]},
        {
            "id": "s2",
            "name": "Wall 2",
            "label": "wall",
            "vertices": [[700, 0], [1280, 0], [1280, 720]],
        },
        {"id": "s3", "name": "Ceiling", "label": "ceiling", "vertices": [[0, 0], [9, 0], [9, 9]]},
        {
            "id": "s4",
            "name": "Surface 1",
            "vertices": [[300, 300], [400, 300], [400, 400], [300, 400]],
            "content": {"type": "effect", "effect": "pulse", "params": {"speed": 1.5}},
        },
    ],
}


def ask(prompt, scene=SCENE):
    return run(RuleAssistant(), scene, prompt)


def by_surface(plan, kind="set_content"):
    return {op["surface"]: op for op in plan.ops if op["op"] == kind}


# Catalog


def test_catalog_matches_what_themes_use():
    cat = catalog()
    assert [e.id for e in cat.effects] == [
        "neon_outline",
        "color_flood",
        "pulse",
        "scanlines",
        "sparkles",
        "edge_trace",
    ]
    for theme in cat.themes:
        for effect_id, params in theme.background + theme.object:
            effect = cat.effect(effect_id)
            assert effect is not None
            assert set(params) <= {p.key for p in effect.params}


def test_settings_are_made_valid_like_in_the_app():
    pulse = catalog().effect("pulse")
    resolved = pulse.resolve({"color": "#ff0000", "speed": 99, "depth": "loud", "extra": 1})
    assert resolved == {"color": "#FF0000", "speed": 4.0, "depth": 0.8}
    assert pulse.resolve({"color": "red", "speed": True})["color"] == "#FFB000"


# Rules


def test_walls_sparkle_and_box_pulses_red():
    plan = ask("make the walls sparkle and the box pulse red")
    content = by_surface(plan)
    assert content["s1"]["content"]["effect"] == "sparkles"
    assert content["s2"]["content"]["effect"] == "sparkles"
    assert content["s4"]["content"]["effect"] == "pulse"
    assert content["s4"]["content"]["params"]["color"] == "#FF2A2A"
    assert "s3" not in content
    assert plan.message == "Wall, Wall 2: sparkles. Surface 1: pulse, red."


def test_same_effect_keeps_its_settings():
    plan = ask("surface 1 pulse blue")
    params = by_surface(plan)["s4"]["content"]["params"]
    assert params["speed"] == 1.5 and params["color"] == "#2E6BFF"


def test_theme_picks_by_role():
    content = by_surface(ask("starry theme"))
    assert content["s1"]["content"]["effect"] == "sparkles"  # wall
    assert content["s4"]["content"]["effect"] == "neon_outline"  # object


def test_targets_carry_over_to_the_clause_that_acts():
    content = by_surface(ask("the walls and the ceiling sparkle"))
    assert set(content) == {"s1", "s2", "s3"}


def test_follow_up_clause_without_target_reuses_the_last_one():
    plan = ask("walls blue scanlines, slower")
    params = by_surface(plan)["s1"]["content"]["params"]
    assert params["speed"] == 0.5 and params["color"] == "#2E6BFF"
    assert "s4" not in by_surface(plan)


def test_name_beats_label():
    assert set(by_surface(ask("wall 2 neon green"))) == {"s2"}


def test_hide_dim_and_clear():
    assert by_surface(ask("hide the ceiling"), "set_visible") == {
        "s3": {"op": "set_visible", "surface": "s3", "visible": False}
    }
    opacity = by_surface(ask("dim everything to 40%"), "set_opacity")
    assert {op["opacity"] for op in opacity.values()} == {0.4} and len(opacity) == 4
    assert by_surface(ask("clear the walls"))["s1"]["content"] == {"type": "none"}


def test_colour_alone_recolours_an_effect_or_fills_with_colour():
    content = by_surface(ask("everything orange"))
    assert content["s4"]["content"]["effect"] == "pulse"
    assert content["s4"]["content"]["params"]["color"] == "#FF7A1A"
    assert content["s1"]["content"] == {"type": "color", "color": "#FF7A1A"}


def test_speeding_up_nothing_says_so():
    plan = ask("ceiling faster")
    assert plan.ops == []
    assert "no effect" in plan.message


def test_nonsense_gets_a_hint_not_a_guess():
    plan = ask("make it pop")
    assert plan.ops == [] and "Try something like" in plan.message


def test_empty_scene():
    plan = ask("sparkle", {**SCENE, "surfaces": []})
    assert plan.ops == [] and "Scan" in plan.message


# The check


def test_check_drops_what_the_app_should_not_get():
    scene = read_scene(SCENE)
    ops = [
        {"op": "set_content", "surface": "s1", "content": {"type": "effect", "effect": "laser"}},
        {"op": "set_opacity", "surface": "nope", "opacity": 0.5},
        {"op": "translate_surface", "surface": "s1", "dx": 5, "dy": 5},
        {"op": "set_opacity", "surface": "s1", "opacity": 3},
        {"op": "set_content", "surface": "s1", "content": {"type": "image", "source": "x.png"}},
        {
            "op": "set_content",
            "surface": "s2",
            "content": {"type": "effect", "effect": "pulse", "params": {"speed": 50}},
        },
        "not even a dict",
    ]
    kept, dropped = check_ops(ops, scene)
    assert kept == [
        {
            "op": "set_content",
            "surface": "s2",
            "content": {
                "type": "effect",
                "effect": "pulse",
                "params": {"color": "#FFB000", "speed": 4.0, "depth": 0.8},
            },
        }
    ]
    assert len(dropped) == 6


def test_bad_scene_is_refused():
    with pytest.raises(SceneError):
        read_scene({"version": 2, "projector": {"width": 1, "height": 1}, "surfaces": []})


# Endpoint


def post(client, body, headers=None):
    return client.post(
        "/v1/assistant",
        content=json.dumps(body),
        headers={"content-type": "application/json", **(headers or {})},
    )


def test_endpoint_returns_checked_ops():
    client = TestClient(create_app(Settings()))
    reply = post(client, {"scene": SCENE, "prompt": "hide the ceiling"})
    assert reply.status_code == 200
    body = reply.json()
    assert body["model"] == "rules"
    assert body["ops"] == [{"op": "set_visible", "surface": "s3", "visible": False}]
    assert body["message"] == "Ceiling: hidden."
    assert client.get("/health").json()["assistant"] == "rules"


@pytest.mark.parametrize(
    ("body", "content_type", "status"),
    [
        ({"scene": SCENE, "prompt": "x"}, "text/plain", 415),
        ({"scene": SCENE}, "application/json", 400),
        ({"scene": SCENE, "prompt": "x" * 501}, "application/json", 400),
        ({"scene": {"version": 1}, "prompt": "sparkle"}, "application/json", 400),
    ],
)
def test_endpoint_refuses_bad_requests(body, content_type, status):
    client = TestClient(create_app(Settings()))
    reply = client.post(
        "/v1/assistant", content=json.dumps(body), headers={"content-type": content_type}
    )
    assert reply.status_code == status


def test_endpoint_needs_the_key_when_set():
    client = TestClient(create_app(Settings(api_key="secret")))
    assert post(client, {"scene": SCENE, "prompt": "x"}).status_code == 401
    assert post(client, {"scene": SCENE, "prompt": "x"}, {"x-api-key": "secret"}).status_code == 200
