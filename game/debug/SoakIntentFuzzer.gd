class_name SoakIntentFuzzer
extends Node
## Client-side authority probe (SOAK_PLAN section 3): sends the SoakFuzzPlan intents, which the
## host must refuse, through MatchNet.submit_place and logs a SOAK_FUZZ line for each. Main
## creates it when `--soak-fuzz` is on the command line in debug mode and sets `config` before
## add_child.

## Fuzz seed, cadence and flood factor.
var config: SoakConfig = null
