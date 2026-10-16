class_name HudFeedbackIconTable
extends Resource
## HUD feedback pictograms (assets/ui/hud/feedback_icons art,
## wired by): held-block height, goal capture, placement rejected
## and placement relocated. Loaded as config/ui/hud_feedback_icon_table.tres so UI
## code never carries asset paths. Presentation only (every peer shows the same
## replicated events). Not an F4 tuning panel resource (no hints entry needed).


enum Feedback { HELD_HEIGHT, CAPTURE, REJECTED, RELOCATED }

@export var held_height: Texture2D = null
@export var capture: Texture2D = null
@export var rejected: Texture2D = null
@export var relocated: Texture2D = null

## Edge of the pictograms in the HUD, in px (asset README: 24-32 px at 1080p).
@export var icon_px: int = 28


## Pictogram for a Feedback value, or null when unknown.
func icon_for(feedback: Feedback) -> Texture2D:
	match feedback:
		Feedback.HELD_HEIGHT:
			return held_height
		Feedback.CAPTURE:
			return capture
		Feedback.REJECTED:
			return rejected
		Feedback.RELOCATED:
			return relocated
	return null
