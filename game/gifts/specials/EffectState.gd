class_name EffectState
extends RefCounted
## Base of the per-activation state one stateful SpecialEffect keeps for its SpecialBehavior
## (SpecialEffect.new_state()). Each effect defines its own inner subclass with typed fields;
## the behaviour only stores and hands it back through SpecialBehavior.state().
