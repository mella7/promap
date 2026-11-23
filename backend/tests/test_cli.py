from PIL import Image

from promap_backend.cli import main


def test_segment_and_depth_write_images(tmp_path, capsys):
    photo = tmp_path / "room.png"
    Image.new("RGB", (480, 360), (120, 120, 120)).save(photo)

    assert main(["segment", str(photo), "--segmenter", "fake"]) == 0
    assert (tmp_path / "room.surfaces.png").exists()
    out = capsys.readouterr().out
    assert "3 surfaces" in out and "loaded in" in out and "run 1:" in out

    assert main(["depth", str(photo), "--depth", "fake"]) == 0
    depth = Image.open(tmp_path / "room.depth.png")
    assert depth.size == (480, 360)


def test_runs_times_each_run(tmp_path, capsys):
    photo = tmp_path / "room.png"
    Image.new("RGB", (120, 90)).save(photo)
    assert main(["depth", str(photo), "--depth", "fake", "--runs", "3"]) == 0
    assert "run 3:" in capsys.readouterr().out


def test_missing_photo_is_reported(tmp_path, capsys):
    assert main(["segment", str(tmp_path / "nope.jpg"), "--segmenter", "fake"]) == 1
    assert "Cannot read" in capsys.readouterr().err


def test_planes_from_depth_alone(tmp_path, capsys):
    photo = tmp_path / "room.png"
    Image.new("RGB", (480, 360)).save(photo)
    assert main(["segment", str(photo), "--segmenter", "planes", "--depth", "fake"]) == 0
    out = capsys.readouterr().out
    assert "planes: loaded" in out and "Wall" in out
