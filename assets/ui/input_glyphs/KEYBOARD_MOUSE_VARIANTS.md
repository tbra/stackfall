# Keyboard and mouse glyph variants

This asset batch adds down/left/right arrows, Enter, Escape, Tab, Space, mouse right/middle, and wheel up/down to the first input glyph package (`Bontago-mp0.37`). `tools/generate_keyboard_mouse_glyphs.py` is the reproducible source.

The keycaps and mouse shell match the first batch's paper fill, ink 3 px edge and coral active area. Arrows and common navigation keys use geometry instead of tiny lettering. The Space key has a wider 96×64 viewBox; the others are 64×64. No font, raster image, SVG filter or external link is used. These are standalone future UI assets; the current `ui/InputGlyph.gd` renderer is unchanged.

At 24 px, keep the mouse wheel direction next to a short localized label when direction is critical. Review on light paper and a dark sky before integration.
