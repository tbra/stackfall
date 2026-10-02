#!/usr/bin/env python3
"""Write the second set of standalone Stackfall gamepad SVG source assets.

The first set (Bontago-mp0.37) establishes A/B, LB and D-pad up. These
variants use the same 64-unit viewBox, ink edge and paper/coral materials.
No font, filter, bitmap, external link or live UI implementation is used.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "assets" / "ui" / "input_glyphs"
INK = "#26323A"
PAPER = "#F5EBD6"
FIELD = "#FFFAF0"
CORAL = "#EB6B5C"


def wrap(title: str, body: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" '
            f'role="img" aria-labelledby="t"><title id="t">{title}</title>'
            f'{body}</svg>\n')


def face(title: str, color: str, letter_path: str) -> str:
    return wrap(title, f'<circle cx="32" cy="32" r="27" fill="{color}" stroke="{INK}" stroke-width="3"/>'
                f'<circle cx="32" cy="32" r="20" fill="none" stroke="{FIELD}" stroke-width="2"/>'
                f'<path d="{letter_path}" fill="{FIELD}"/>')


def dpad(title: str, direction: str) -> str:
    arms = {"down": (24, 40, 16, 19), "left": (5, 24, 19, 16), "right": (40, 24, 19, 16)}
    x, y, width, height = arms[direction]
    return wrap(title, f'<path d="M24 5h16v19h19v16H40v19H24V40H5V24h19Z" fill="{PAPER}" '
                f'stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
                f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="{CORAL}"/>'
                f'<path d="M24 5h16v19h19v16H40v19H24V40H5V24h19Z" fill="none" '
                f'stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
                f'<circle cx="32" cy="32" r="4" fill="{INK}"/>')


def cap(title: str, label: str, trigger: bool = False) -> str:
    profile = ('<path d="M5 18q0-7 9-7h36q9 0 9 7v26q0 10-10 10H15Q5 54 5 44Z" '
               if trigger else '<rect x="4" y="11" width="56" height="43" rx="13" ')
    profile += f'fill="{PAPER}" stroke="{INK}" stroke-width="3"/>'
    baseline = f'<path d="M7 43h50" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
    if label == "RB":
        text = '<path d="M16 42V22h9q8 0 8 6 0 5-6 6l7 8M16 33h10M40 22v20h8q7 0 7-5 0-4-6-5 5-1 5-5 0-5-7-5Z" fill="none" stroke="#26323A" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>'
    elif label == "LT":
        text = '<path d="M15 22v20h17M35 22h19M44 22v20" fill="none" stroke="#26323A" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'
    else:
        text = '<path d="M12 42V22h9q8 0 8 6 0 5-6 6l7 8M12 33h10M34 22h19M43 22v20" fill="none" stroke="#26323A" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>'
    return wrap(title, profile + baseline + text)


def stick(title: str, side: str) -> str:
    letter = ('<path d="M27 25v15h12" fill="none" stroke="#26323A" stroke-width="4" '
              'stroke-linecap="round" stroke-linejoin="round"/>' if side == "left" else
              '<path d="M25 40V25h8q6 0 6 5t-6 5h-8m8 0 7 5" fill="none" stroke="#26323A" '
              'stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>')
    return wrap(title, f'<circle cx="32" cy="32" r="27" fill="{PAPER}" stroke="{INK}" stroke-width="3"/>'
                f'<circle cx="32" cy="32" r="19" fill="{FIELD}" stroke="{INK}" stroke-width="2"/>'
                f'<circle cx="32" cy="32" r="14" fill="#75CBD1"/>{letter}')


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    assets = {
        "gamepad_x.svg": face("Gamepad X button", "#4D87D4", "M20 18h7l5 9 5-9h7l-9 14 9 14h-7l-5-9-5 9h-7l9-14Z"),
        "gamepad_y.svg": face("Gamepad Y button", "#DEBD3D", "M19 18h7l6 11 6-11h7L35 35v11h-6V35Z"),
        "gamepad_rb.svg": cap("Gamepad right shoulder button", "RB"),
        "gamepad_lt.svg": cap("Gamepad left trigger", "LT", True),
        "gamepad_rt.svg": cap("Gamepad right trigger", "RT", True),
        "gamepad_dpad_down.svg": dpad("Gamepad D-pad down", "down"),
        "gamepad_dpad_left.svg": dpad("Gamepad D-pad left", "left"),
        "gamepad_dpad_right.svg": dpad("Gamepad D-pad right", "right"),
        "gamepad_stick_left.svg": stick("Gamepad left stick", "left"),
        "gamepad_stick_right.svg": stick("Gamepad right stick", "right"),
    }
    for name, content in assets.items():
        (ROOT / name).write_text(content, encoding="utf-8")
    print(f"Wrote {len(assets)} gamepad SVG assets to {ROOT}")


if __name__ == "__main__":
    main()
