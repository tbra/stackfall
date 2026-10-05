class_name GiftFxPresenter
extends Node
## Central dispatcher for gift effect visuals on clients.
##
## Subscribes once to Events.special_triggered and routes each event to a
## def-id based builder table (Callable). Replaces inline handlers that were
## previously in Match (e.g., _on_paintball_triggered, _on_black_hole_triggered).
## Handlers should be safe-to-call on null positions (out-of-bounds teleport).
##
## Depends on: Events, SpecialDef, Block


## Receives special_triggered events and dispatches to registered handlers by def_id.
## Handlers are Callables that accept (Block, SpecialDef, position: Vector3).
