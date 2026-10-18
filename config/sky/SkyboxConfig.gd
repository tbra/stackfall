class_name SkyboxConfig
extends Resource
## Tunables for game/sky/Skybox.gd.

## The launch sky id: a locked sky ("sunset", "dawn" or "night"; Skybox locks the cycle at
## SkyCycleDef.locked_phase_for(id)) or "cycle" for the running day/night cycle. The name is kept
## so saved F4 overrides and fixtures keep working. DECISION: a SkyboxConfig field rather than a
## MapDef/MatchConfig one, so choosing a night look touches no gameplay or network-synced resource.
@export var theme_name: String = "sunset"
