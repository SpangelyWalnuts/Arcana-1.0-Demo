extends Resource
class_name AIProfile

@export var id: StringName = &""

# -----------------------------
# Movement / scoring tuning
# -----------------------------
@export var move_cost_weight: float = 0.75
@export var defense_weight: float = 0.75
@export var hazard_weight: float = 0.0
@export var threat_bonus: float = 5.0
@export var prefer_threat_tiles: bool = true

# Hold-vs-move decision
@export var hold_margin_base: float = 0.75
@export var hold_margin_defense_role: float = 1.25
@export var hold_margin_support_role: float = 0.75
@export var hold_margin_offense_role: float = 0.25

# -----------------------------
# Arcana (casting) tuning
# -----------------------------
@export var arcana_intent_enabled: bool = true

# Buff casting distance gating
@export var buff_cast_min_player_distance: int = 6
@export var buff_cast_when_rooted: bool = true

# -----------------------------
# Turn decision ordering
# -----------------------------
# Allowed:
# &"cast_first"  (default / current behavior)
# &"attack_first"
# &"move_first"
# &"wait_first" (attack if in range, otherwise do nothing)
@export var opening_priority: StringName = &"cast_first"
