class_name SkyboxConfig
extends Resource
## Tunables for game/sky/Skybox.gd.

## id of the SkyThemeDef (res://config/sky/themes/<id>.tres)
## Skybox applies at start-up. DECISION: a SkyboxConfig field rather than a
## MapDef/MatchConfig one, so choosing a night look touches no gameplay or
## network-synced resource; "sunset" (the default) keeps Skybox's own preloaded
## theme export untouched.
@export var theme_name: String = "sunset"
