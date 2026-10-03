"""Embed the transparent silhouette layers into a standalone preview SVG."""

from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
PREVIEW = ROOT / "docs/art_mockups/cosmic_horizon_silhouette_preview.svg"
LAYERS = ROOT / "assets/maps/cosmic_horror"


def main() -> None:
    tree = ET.parse(PREVIEW)
    group = tree.getroot().find(f".//{{{NS}}}g[@id='asset-layers']")
    if group is None:
        raise ValueError("Preview lacks asset-layers group")
    group.clear()
    group.set("id", "asset-layers")
    group.set("transform", "translate(0 40)")
    for name in ("horizon_tendrils", "horizon_body", "horizon_crown"):
        layer = ET.parse(LAYERS / f"{name}.svg").getroot()
        wrapper = ET.SubElement(group, f"{{{NS}}}g", {"id": name})
        wrapper.extend(list(layer))
    tree.write(PREVIEW, encoding="unicode", xml_declaration=True)
    print(f"Embedded 3 source layers into {PREVIEW.relative_to(ROOT)}")



if __name__ == "__main__":
    main()
