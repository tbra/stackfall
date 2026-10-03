# Menu action icon candidates

Six standalone 32×32 SVGs for Play, Host, Join, Settings, Back, and Quit. The existing live icon paths are unchanged. Each source has an SVG title and accessible label. The strokes and color blocks match `docs/ART_DESIGN_SYSTEM.md` in the separate design-system worktree (`Bontago-mp0.38`).

`docs/art_mockups/menu_icons_art_v1.svg` and its PNG render compare the sources at 48, 32, and 24 px. The 24 px row uses a paper badge over a dark tile: these dark-ink icons require a light surface. Keep a light badge if they appear over sky or storm. They remain distinct by shape without their accent colors.

Generation: `python tools/generate_menu_icon_art.py`. The script writes the six SVGs and the review SVG. The PNG is an inspected render of the review SVG. Review the icons beside actual menu labels before replacing any live asset.
