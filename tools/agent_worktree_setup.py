"""Write an untracked override.cfg into an agent worktree (Bontago-fca.2).

Godot's --windowed flag does not override a project whose
display/window/size/mode is fullscreen (main.cpp only skips the other
window flags), so agent runs flashed fullscreen before AgentProbe resized
them. Godot loads res://override.cfg over project.godot at startup, so an
agent-only override makes every window start tiny, windowed, off-screen,
unfocused and muted from the first frame. Never write this into the
owner's main checkout (M:/Bontago).

Usage: python tools/agent_worktree_setup.py <worktree> [<worktree> ...]
"""
import pathlib
import sys

OVERRIDE = """; Agent-only (tools/agent_worktree_setup.py, Bontago-fca.2). Untracked.
[display]

window/size/mode=0
window/size/borderless=false
window/size/no_focus=true
window/size/window_width_override=320
window/size/window_height_override=180
window/size/initial_position_type=0
window/size/initial_position=Vector2i(10000, 10000)

[audio]

driver/driver="Dummy"
"""

MAIN_CHECKOUT = pathlib.Path("M:/Bontago").resolve()


def main(argv: "list[str]") -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    for raw in argv[1:]:
        root = pathlib.Path(raw).resolve()
        if root == MAIN_CHECKOUT:
            print(f"refusing to write override.cfg into the owner's main checkout {root}")
            return 1
        if not (root / "project.godot").is_file():
            print(f"not a Godot project: {root}")
            return 1
        (root / "override.cfg").write_text(OVERRIDE, encoding="utf-8")
        print(f"wrote {root / 'override.cfg'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
