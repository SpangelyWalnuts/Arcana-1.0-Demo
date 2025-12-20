extends Node2D

# --- Mana / Skills ---
var max_mana: int = 5
var mana: int = 5
var mana_regen_per_turn: int = 1
var skills: Array = []   # array of Skill resources
var level: int = 1
var exp: int = 0
var unit_data: UnitData = null
@export var ai_profile: AIProfile = null

@export var unit_class: UnitClass
@export var is_active: bool = true
@export var attack_anim_name: StringName = &"attack"
@export var cast_anim_name: StringName = &"cast"

var _is_dying: bool = false
var grid_position: Vector2i
var move_range: int = 4
var active_statuses: Array = []  # list of Dictionaries for now

var team: String = "player"   # "player" or "enemy"
var has_acted: bool = false

var max_hp: int = 10
var hp: int = 10
var atk: int = 4
var defense: int = 1
var attack_range: int = 1

# --- Enemy intent icon support ---
@onready var intent_icon: TextureRect = $IntentIcon
@onready var boss_icon: TextureRect = $BossIcon

@export var boss_icon_texture: Texture2D

@export var intent_attack_texture: Texture2D
@export var intent_move_texture: Texture2D
@export var intent_wait_texture: Texture2D
@export var intent_cast_texture: Texture2D  # NEW
@export var intent_boss_texture: Texture2D

var _intent_tween: Tween = null
var _intent_last_shown: String = ""


var current_intent: String = ""  # "attack", "move", "wait", or ""

@onready var hp_bg: ColorRect   = $HPBar/BG
@onready var hp_fill: ColorRect = $HPBar/Fill
@onready var status_icons_root: HBoxContainer = $StatusIcons
@onready var sprite_static: Sprite2D = $Sprite2D
@onready var sprite_anim: AnimatedSprite2D = $AnimatedSprite2D

# Used for KO FX; works with both Sprite2D and AnimatedSprite2D
var sprite: CanvasItem

#HELPERS
func add_status(status: Dictionary) -> void:
	active_statuses.append(status)


func has_status_flag(flag: String) -> bool:
	for st in active_statuses:
		if st is Dictionary and st.get(flag, false):
			return true
	return false

#CLASS SPRITE HELPER
func _apply_class_visuals() -> void:
	# Prefer animation if provided by the class
	if unit_class != null and unit_class.idle_frames != null:
		sprite_anim.sprite_frames = unit_class.idle_frames
		sprite_anim.animation = unit_class.idle_anim_name
		sprite_anim.visible = true
		sprite_anim.play()

		sprite_static.visible = false
		sprite = sprite_anim
		return

	# Fallback: static sprite texture (or whatever is already in Sprite2D)
	if unit_class != null and unit_class.sprite_texture != null:
		sprite_static.texture = unit_class.sprite_texture

	sprite_static.visible = true
	sprite_anim.visible = false
	sprite = sprite_static

func _ready() -> void:
	if not is_active:
		return

	# 1) Decide source of class / level / exp
	if unit_data != null and unit_data.unit_class != null:
		# If we have UnitData, let it drive everything
		unit_class = unit_data.unit_class
		level = unit_data.level
		exp   = unit_data.exp
	elif unit_class != null:
		# Fallback: class only, no UnitData
		level = 1
		exp   = 0

	# 2) Base stats from class (or some safe defaults if no class)
	if unit_class != null:
		max_hp       = unit_class.max_hp
		atk          = unit_class.atk
		defense      = unit_class.defense
		attack_range = unit_class.attack_range
		move_range   = unit_class.move_range

		# DO **NOT** override team here anymore.
		max_mana            = unit_class.max_mana
		mana_regen_per_turn = unit_class.mana_regen_per_turn
	else:
		# In case something was spawned without a class at all
		max_hp       = 10
		atk          = 1
		defense      = 0
		attack_range = 1
		move_range   = 4
		max_mana     = 0
		mana_regen_per_turn = 0

	# 3) Apply permanent per-unit bonuses from UnitData (level-ups, artifacts, etc.)
	if unit_data != null:
		level = unit_data.level
		exp   = unit_data.exp

		max_hp       += unit_data.bonus_max_hp
		atk          += unit_data.bonus_atk
		defense      += unit_data.bonus_defense
		move_range   += unit_data.bonus_move
		max_mana     += unit_data.bonus_max_mana

	# 4) Apply equipment bonuses on top
	if unit_data != null and unit_data.equipment_slots.size() > 0:
		for eq in unit_data.equipment_slots:
			if eq == null:
				continue
			var e := eq as Equipment
			if e == null:
				continue

			max_hp     += e.bonus_max_hp
			atk        += e.bonus_atk
			defense    += e.bonus_defense
			move_range += e.bonus_move
			max_mana   += e.bonus_max_mana

	# 5) Finally set current HP / Mana to the *final* max values
	hp   = max_hp
	mana = max_mana

# 6) Decide skills:
# - Enemies: ONLY equipped arcana (so arcana_chance is truthful)
# - Players: prefer equipped arcana, otherwise class defaults
	if team == "enemy":
		if unit_data != null and unit_data.equipped_arcana.size() > 0:
			skills = unit_data.equipped_arcana.duplicate()
		else:
			skills = []
	else:
		if unit_data != null and unit_data.equipped_arcana.size() > 0:
			skills = unit_data.equipped_arcana.duplicate()
		elif unit_class != null:
			skills = unit_class.skills.duplicate()
		else:
			skills = []


	# 7) Add to correct group
	# If team somehow isn't set, default to player.
	if team != "player" and team != "enemy":
		team = "player"

	if team == "player":
		add_to_group("player_units")
	elif team == "enemy":
		add_to_group("enemy_units")
	# Hide intent icon for player units by default
	if team == "player":
		set_intent_icon("")

	# Cache status icon root if present
	if has_node("StatusIcons"):
		status_icons_root = $StatusIcons
		
	# 6.5) Set sprite based on UnitClass
	_apply_class_visuals()


	_update_hp_bar()
	refresh_status_icons()  # start empty, but keeps UI clean
	_refresh_boss_icon()

	# 🔹 Listen for status changes (to update icons)
	if StatusManager != null:
		StatusManager.status_changed.connect(_on_status_changed)

func _on_status_changed(changed_unit) -> void:
	if changed_unit == self:
		refresh_status_icons()

func regenerate_mana() -> void:
	var bonus_regen: int = 0
	if StatusManager != null:
		# If you use Autoload named StatusManager
		bonus_regen = StatusManager.get_mana_regen_bonus(self)

	mana += mana_regen_per_turn + bonus_regen
	if mana > max_mana:
		mana = max_mana




func reset_for_new_turn() -> void:
	has_acted = false
	regenerate_mana()
	# Later, when you add duration ticking, you'll update active_statuses
	# and then call refresh_status_icons() here.



func is_enemy_of(other) -> bool:
	return team != other.team


func take_damage(amount: int) -> bool:
	hp -= amount
	print(name, " took ", amount, " damage. HP now: ", hp)

	_update_hp_bar()

	if hp <= 0:
		die()
		return false

	return true


signal died

func die() -> void:
	if _is_dying:
		return
	_is_dying = true

	print(name, " has been defeated.")

	# Notify listeners (Main.gd, etc.)
	died.emit()

	# Make sure we are no longer in unit groups (important for victory checks)
	if team == "enemy":
		remove_from_group("enemy_units")
	elif team == "player":
		remove_from_group("player_units")
	# NEW: boss objective support
	# If this unit is a boss, remove immediately so DEFEAT_BOSS triggers on death,
	# not after the KO tween finishes.
	if is_in_group("boss"):
		remove_from_group("boss")

	# Prevent further interactions
	set_process(false)
	set_physics_process(false)
	has_acted = true

	# Play KO effect without blocking callers
	_death_fx_sequence()

func _death_fx_sequence() -> void:
	# If we don't have a sprite, just vanish quickly
	if sprite == null or not is_instance_valid(sprite):
		queue_free()
		return

	var original: Color = sprite.modulate

	# Flash white (bright) then fade out
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(2, 2, 2, 1), 0.05)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate", original, 0.05)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await tween.finished
	queue_free()


func _update_hp_bar() -> void:
	if hp_fill == null or hp_bg == null:
		return

	var ratio: float = clamp(float(hp) / float(max_hp), 0.0, 1.0) as float

	# Use the background bar width as the "full" width
	var full_width: float = hp_bg.size.x
	hp_fill.size.x = full_width * ratio

func update_hp_bar() -> void:
	_update_hp_bar()


# -------------------------------------------------
#  STATUS + UI HELPERS
# -------------------------------------------------


func can_move() -> bool:
	return not has_status_flag("prevent_move")

func can_cast_arcana() -> bool:
	return not has_status_flag("prevent_arcana")

func refresh_status_icons() -> void:
	if status_icons_root == null:
		return
	StatusManager.refresh_icons_for_unit(self, status_icons_root)


#Intent icon helper
func set_intent_icon(intent: String) -> void:
	_refresh_boss_icon()
	current_intent = intent

	if intent_icon == null:
		return

	# --- BOSS OVERRIDE ---
# If this unit is a boss, always show the boss icon regardless of intent.
# Uses group first, meta as backup.
	var is_boss := is_in_group("boss") or (has_meta("is_boss") and bool(get_meta("is_boss")))
	if is_boss:
		intent_icon.texture = intent_boss_texture if intent_boss_texture != null else intent_attack_texture
		if intent_icon is Control:
			intent_icon.tooltip_text = "BOSS"

	# Ensure it's visible (no pop logic needed, but keep it consistent)
		intent_icon.visible = true
		intent_icon.modulate.a = 1.0
		intent_icon.scale = Vector2.ONE
		_intent_last_shown = "__boss__"
		return

	var tex: Texture2D = null
	var tooltip: String = ""

	match intent:
		"attack":
			tex = intent_attack_texture
			tooltip = "Will attack if in range."
		"cast":
			# If AI stored a specific Arcana skill, show its icon
			var s = null
			if has_meta("intent_skill"):
				s = get_meta("intent_skill")

			if s != null and s.has_method("get"):
				var icon_tex = s.get("icon_texture")
				if icon_tex is Texture2D:
					tex = icon_tex
				else:
					tex = intent_cast_texture

				var nm = s.get("name")
				tooltip = "Will cast: %s" % str(nm)
			else:
				tex = intent_cast_texture
				tooltip = "Will cast Arcana."
		"move":
			tex = intent_move_texture
			tooltip = "Will move toward the nearest target."
		"wait":
			tex = intent_wait_texture
			tooltip = "Cannot move or will wait this turn."
		_:
			tex = null
			tooltip = ""

	# Apply texture + tooltip
	intent_icon.texture = tex
	if intent_icon is Control:
		intent_icon.tooltip_text = tooltip

	# Stop old tween cleanly
	if _intent_tween != null and is_instance_valid(_intent_tween):
		_intent_tween.kill()
		_intent_tween = null

	# If clearing intent -> fade out then hide
	if tex == null:
		_intent_last_shown = ""
		if intent_icon.visible:
			_intent_tween = create_tween()
			_intent_tween.tween_property(intent_icon, "modulate:a", 0.0, 0.12)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_intent_tween.finished.connect(func():
				if intent_icon != null and is_instance_valid(intent_icon):
					intent_icon.visible = false
					intent_icon.modulate.a = 1.0
					intent_icon.scale = Vector2.ONE
			, CONNECT_ONE_SHOT)
		else:
			intent_icon.visible = false
		return

# If same intent as last time, just ensure visible (no re-pop spam)
# ✅ Also force full alpha/scale in case a previous tween got interrupted (hit-stop/time_scale)
	if intent == _intent_last_shown and intent_icon.visible:
		intent_icon.modulate.a = 1.0
		intent_icon.scale = Vector2.ONE
		return


	_intent_last_shown = intent

	# Pop in: show + fade from 0 + small scale bounce
	intent_icon.modulate = Color(1, 1, 1, 1)
	intent_icon.visible = true
	intent_icon.modulate.a = 0.0
	intent_icon.scale = Vector2.ONE * 0.85

	_intent_tween = create_tween()
	_intent_tween.set_parallel(true)

	_intent_tween.tween_property(intent_icon, "modulate:a", 1.0, 0.12)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_intent_tween.tween_property(intent_icon, "scale", Vector2.ONE * 1.08, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# settle back to 1.0
	var settle := create_tween()
	settle.tween_property(intent_icon, "scale", Vector2.ONE, 0.08)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

#BOSS ICON HELPER
func _refresh_boss_icon() -> void:
	if boss_icon == null:
		return

	var is_boss := is_in_group("boss") or (has_meta("is_boss") and bool(get_meta("is_boss")))
	if is_boss:
		boss_icon.texture = boss_icon_texture
		boss_icon.visible = true
		boss_icon.modulate.a = 1.0
		boss_icon.scale = Vector2.ONE
		if boss_icon is Control:
			boss_icon.tooltip_text = "BOSS"
	else:
		boss_icon.visible = false


#ANIMATION HELPERS
func play_attack_anim(target_world_pos: Vector2) -> void:
	# Prefer sprite-sheet attack animation if we have one
	if sprite != null and is_instance_valid(sprite) and sprite is AnimatedSprite2D:
		var a := sprite as AnimatedSprite2D
		if a.sprite_frames != null and a.sprite_frames.has_animation(attack_anim_name):
			# Play attack once, then blend back to idle
			a.play(attack_anim_name)

			# one-shot return to idle (avoid stacking connections)
			if a.animation_finished.is_connected(_on_attack_anim_finished):
				a.animation_finished.disconnect(_on_attack_anim_finished)
			a.animation_finished.connect(_on_attack_anim_finished, CONNECT_ONE_SHOT)
			return

	# Fallback: sprite-only lunge (works for Sprite2D OR AnimatedSprite2D)
	if sprite == null or not is_instance_valid(sprite):
		return
	if not (sprite is Node2D):
		return

	var spr := sprite as Node2D
	var start_local := spr.position

	var unit_world := global_position
	var dir := target_world_pos - unit_world
	if dir.length() > 0.001:
		dir = dir.normalized()
	else:
		dir = Vector2.RIGHT

	var lunge_dist := 14.0
	var lunge_local := start_local + dir * lunge_dist

	var tween := create_tween()
	tween.tween_property(spr, "position", lunge_local, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(spr, "position", start_local, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

#ATTACK ANIM HELPER
func _on_attack_anim_finished() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if not (sprite is AnimatedSprite2D):
		return

	var a := sprite as AnimatedSprite2D

	# Return to class idle if defined, else "idle"
	var idle_name: StringName = &"idle"
	if unit_class != null and unit_class.idle_anim_name != StringName():
		idle_name = unit_class.idle_anim_name

	if a.sprite_frames != null and a.sprite_frames.has_animation(idle_name):
		a.play(idle_name)
	else:
		# If no idle exists, stop on last frame
		a.stop()


func play_cast_anim() -> void:
	# Prefer sprite-sheet cast animation if we have one
	if sprite != null and is_instance_valid(sprite) and sprite is AnimatedSprite2D:
		var a := sprite as AnimatedSprite2D
		if a.sprite_frames != null and a.sprite_frames.has_animation(cast_anim_name):
			a.play(cast_anim_name)

			# one-shot return to idle (avoid stacking connections)
			if a.animation_finished.is_connected(_on_cast_anim_finished):
				a.animation_finished.disconnect(_on_cast_anim_finished)
			a.animation_finished.connect(_on_cast_anim_finished, CONNECT_ONE_SHOT)
			return

	# Fallback: glow pulse (your existing behavior)
	if sprite == null or not is_instance_valid(sprite):
		return

	var s := sprite as CanvasItem
	var orig := s.modulate

	var tween := create_tween()
	tween.tween_property(s, "modulate", Color(orig.r * 1.4, orig.g * 1.4, orig.b * 1.4, orig.a), 0.08)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(s, "modulate", orig, 0.10)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

#CAST ANIM HELPER
func _on_cast_anim_finished() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if not (sprite is AnimatedSprite2D):
		return

	var a := sprite as AnimatedSprite2D

	# Return to class idle if defined, else "idle"
	var idle_name: StringName = &"idle"
	if unit_class != null and unit_class.idle_anim_name != StringName():
		idle_name = unit_class.idle_anim_name

	if a.sprite_frames != null and a.sprite_frames.has_animation(idle_name):
		a.play(idle_name)
	else:
		a.stop()


func play_hit_react() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return

	var s := sprite as CanvasItem
	var orig := s.modulate

	var tween := create_tween()
	tween.tween_property(s, "modulate", Color(1.6, 0.8, 0.8, orig.a), 0.04)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(s, "modulate", orig, 0.08)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
