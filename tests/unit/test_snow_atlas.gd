extends GutTest
## Bontago-mp0.121: the falling flakes draw random cells of the cel snowflake
## atlas (assets/vfx/snow_atlas_v1) through the flake shader material.

const ATLAS_PATH: String = "res://assets/vfx/snow_atlas_v1/snow_atlas.png"
const SHADER_PATH: String = "res://shaders/weather/snow_flake.gdshader"
const EXPECTED_FRAMES: int = 16

var _snow: SnowPresentation = null


func before_each() -> void:
	_snow = (load("res://vfx/weather/snow_presentation.tscn") as PackedScene).instantiate() as SnowPresentation
	add_child_autofree(_snow)
	_snow.set_process(false)


func _material() -> ShaderMaterial:
	return (_snow.particles().draw_pass_1 as QuadMesh).material as ShaderMaterial


func test_material_uses_the_atlas_texture() -> void:
	var material: ShaderMaterial = _material()
	assert_eq(material.shader.resource_path, SHADER_PATH)
	assert_true(bool(material.get_shader_parameter(&"use_atlas")))
	var texture: Texture2D = material.get_shader_parameter(&"atlas") as Texture2D
	assert_not_null(texture)
	assert_eq(texture.resource_path, ATLAS_PATH)


func test_atlas_grid_has_the_right_frame_count() -> void:
	var grid: Vector2 = _material().get_shader_parameter(&"atlas_grid") as Vector2
	assert_eq(int(grid.x) * int(grid.y), EXPECTED_FRAMES)
	var texture: Texture2D = _material().get_shader_parameter(&"atlas") as Texture2D
	assert_eq(texture.get_width() % int(grid.x), 0, "cells divide the atlas evenly")
	assert_eq(texture.get_height() % int(grid.y), 0)


func test_no_atlas_falls_back_to_the_dot() -> void:
	var tuning: SnowTuning = _snow.tuning.duplicate() as SnowTuning
	tuning.flake_atlas = null
	var other: SnowPresentation = (load("res://vfx/weather/snow_presentation.tscn") as PackedScene).instantiate() as SnowPresentation
	other.tuning = tuning
	add_child_autofree(other)
	var material: ShaderMaterial = (other.particles().draw_pass_1 as QuadMesh).material as ShaderMaterial
	assert_false(bool(material.get_shader_parameter(&"use_atlas")))
