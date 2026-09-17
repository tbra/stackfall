extends Node
## Match configuration and host-side state machine.
##
## Lobby -> Loading -> Countdown -> Playing -> (SuddenDeath) -> End -> Lobby
## (spec 3.7). Implemented from M2 onward.
