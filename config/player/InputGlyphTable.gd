class_name InputGlyphTable
extends Resource
## Colours of the Stackfall Arcade pad face-button caps drawn by ui/InputGlyph (static helpers only;
## the old paper-and-ink stick/chord art table is gone).

## Stackfall Arcade pad face-button caps (KeyPrompt): A mint, B flare,
## X player-2 blue, Y rim gold, all read from ArcadeVisualTuning (single source of the colours).
## Returns the face colour, or TRANSPARENT for a button that is not a face button.
static func face_button_color(button: int, arcade: ArcadeVisualTuning) -> Color:
	match button:
		JOY_BUTTON_A:
			return arcade.mint_color
		JOY_BUTTON_B:
			return arcade.flare_color
		JOY_BUTTON_X:
			return arcade.player_2_color
		JOY_BUTTON_Y:
			return arcade.rim_color
	return Color.TRANSPARENT


## The dark lower lip of a face-button cap; Color.TRANSPARENT lets the block recipe derive it.
static func face_button_lip_color(button: int, arcade: ArcadeVisualTuning) -> Color:
	match button:
		JOY_BUTTON_A:
			return arcade.mint_lip_color
		JOY_BUTTON_B:
			return arcade.flare_lip_color
		JOY_BUTTON_Y:
			return arcade.rim_lip_color
	return Color.TRANSPARENT
