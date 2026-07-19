from pathlib import Path
from PIL import Image
from pipeline.osm_parse import parse_osm
from pipeline.minimap import render_minimap

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_minimap_renders(tmp_path):
    city = parse_osm(FIX)
    block = render_minimap(city, tmp_path / "minimap.png", size=512)
    img = Image.open(tmp_path / "minimap.png")
    assert img.size == (512, 512)
    assert block["px"] == 512 and block["file"] == "minimap.png"
    colors = {c for _, c in img.getcolors(maxcolors=100000)}
    assert (62, 110, 138) in colors      # water drawn
    assert len(colors) >= 3              # bg + water + roads at least

def test_minimap_deterministic(tmp_path):
    city = parse_osm(FIX)
    render_minimap(city, tmp_path / "a.png", size=256)
    render_minimap(city, tmp_path / "b.png", size=256)
    assert (tmp_path / "a.png").read_bytes() == (tmp_path / "b.png").read_bytes()
