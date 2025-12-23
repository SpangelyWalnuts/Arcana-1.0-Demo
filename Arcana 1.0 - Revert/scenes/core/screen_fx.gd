extends CanvasLayer

@onready var cast_dimmer: ColorRect = $CastDimmer

@export var cast_dim_alpha: float = 0.40
@export var cast_dim_in_time: float = 0.08
@export var cast_dim_out_time: float = 0.10

var _tween: Tween

func set_cast_dim(enabled: bool) -> void:
	if cast_dimmer == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()

	var target_a: float = cast_dim_alpha if enabled else 0.0

	# Ensure base color alpha is 0 before tweening (and RGB is black)
	var c := cast_dimmer.color
	c.r = 0.0
	c.g = 0.0
	c.b = 0.0
	# don't force c.a here; tween will handle it
	cast_dimmer.color = c

	_tween = create_tween()
	_tween.tween_property(cast_dimmer, "color:a", target_a,
		cast_dim_in_time if enabled else cast_dim_out_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	print("[ScreenFX] set_cast_dim(", enabled, ") target_a=", target_a, " current_a=", cast_dimmer.color.a)

func impact_flash(flash_alpha: float = 0.12, flash_time: float = 0.08) -> void:
	if cast_dimmer == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()

	# Current dim alpha (what we return to)
	var base_a: float = cast_dim_alpha

	_tween = create_tween()
	# Dip to a lower alpha (brighter), then return to base dim
	_tween.tween_property(cast_dimmer, "color:a", flash_alpha, flash_time * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(cast_dimmer, "color:a", base_a, flash_time * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
