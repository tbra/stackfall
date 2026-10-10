class_name ExitRelease
extends RefCounted
## Bontago-xtq.44: drops the process-wide static caches (shared config tables, the special
## roster, block meshes and materials) when the game scene leaves the tree on quit. Static
## variables outlive the scene tree, so every Texture/Mesh/Material they held was reported
## by the engine as a leaked RID / ObjectDB instance at exit. Called only on exit; nothing
## here changes behaviour while the game runs (a cache rebuilds lazily if used again).


static func release_all() -> void:
	SpecialDef.release_cache()
	BlockMeshBuilder.clear_cache()
	BlockFactory.release_caches()
	GiftModelTable.release_shared()
	GiftIconTable.release_shared()
	HudFeedbackIconTable.release_shared()
	InputGlyphTable.release_shared()
	UiArtTable.release_shared()
	DiscSizeTuning.release_shared()
	UiScaleTuning.release_shared()
	GhostPreview.release_statics()
	InputGlyph.release_statics()
	MenuStyleFactory.release_statics()
	SnowCaps.release_statics()
	HoneyCoat.release_statics()
