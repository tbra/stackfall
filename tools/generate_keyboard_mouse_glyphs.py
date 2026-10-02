#!/usr/bin/env python3
"""Write source SVGs for common keyboard navigation and mouse prompts.

Complements the first eight input glyphs (Bontago-mp0.37). All art is
standalone vector geometry with no font or bitmap dependency.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "assets" / "ui" / "input_glyphs"
INK = "#26323A"
PAPER = "#F5EBD6"
CORAL = "#EB6B5C"


def svg(title: str, body: str, width: int = 64) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} 64" '
            f'role="img" aria-labelledby="t"><title id="t">{title}</title>{body}</svg>\n')


def key(title: str, mark: str, width: int = 64) -> str:
    return svg(title, f'<rect x="5" y="5" width="{width - 10}" height="54" rx="12" '
               f'fill="{PAPER}" stroke="{INK}" stroke-width="3"/>'
               f'<path d="M7 49h{width - 14}" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
               f'<g fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round" '
               f'stroke-linejoin="round">{mark}</g>', width)


def mouse(title: str, active: str, wheel: bool = False) -> str:
    shell = (f'<path d="M13 28a19 19 0 0 1 38 0v13a19 19 0 0 1-38 0Z" '
             f'fill="{PAPER}" stroke="{INK}" stroke-width="3"/>')
    if wheel:
        inner = (f'<path d="M13 28h38M32 9v19" fill="none" stroke="{INK}" stroke-width="3"/>'
                 f'<rect x="28" y="14" width="8" height="17" rx="4" fill="{PAPER}" '
                 f'stroke="{INK}" stroke-width="2"/>{active}'
                 f'<rect x="28" y="14" width="8" height="17" rx="4" fill="none" '
                 f'stroke="{INK}" stroke-width="2"/>')
    else:
        inner = active + (f'<path d="M32 9v19h19M13 28h38" fill="none" '
                          f'stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')
    return svg(title, shell + inner + f'<path d="M24 52q8 5 16 0" fill="none" stroke="{INK}" '
               'stroke-width="2" stroke-linecap="round"/>')


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    marks = {
        "key_down.svg": key("Down arrow key", '<path d="M32 21v21m-13-13 13 13 13-13"/>'),
        "key_left.svg": key("Left arrow key", '<path d="M43 32H21m13-13L21 32l13 13"/>'),
        "key_right.svg": key("Right arrow key", '<path d="M21 32h22M30 19l13 13-13 13"/>'),
        "key_enter.svg": key("Enter key", '<path d="M43 20v12q0 8-8 8H22m10-10L22 40l10 10"/>'),
        "key_escape.svg": key("Escape key", '<path d="M35 19h9v26h-9M36 32H20m7-7-7 7 7 7"/>'),
        "key_tab.svg": key("Tab key", '<path d="M18 25h26m-12-9 12 9-12 9M18 42h28"/>'),
        "key_space.svg": key("Space key", '<path d="M22 30v11h52V30"/>', 96),
        "mouse_right.svg": mouse("Right mouse button", f'<path d="M32 9a19 19 0 0 1 19 19H32Z" fill="{CORAL}"/>'),
        "mouse_middle.svg": mouse("Middle mouse button", f'<path d="M28 14h8v16h-8Z" fill="{CORAL}"/>'),
        "mouse_wheel_up.svg": mouse("Mouse wheel up", f'<path d="M28 18a4 4 0 0 1 8 0v4h-8Z" fill="{CORAL}"/>', True),
        "mouse_wheel_down.svg": mouse("Mouse wheel down", f'<path d="M28 23h8v4a4 4 0 0 1-8 0Z" fill="{CORAL}"/>', True),
    }
    for filename, content in marks.items():
        (ROOT / filename).write_text(content, encoding="utf-8")
    print(f"Wrote {len(marks)} keyboard and mouse glyphs")


if __name__ == "__main__":
    main()
