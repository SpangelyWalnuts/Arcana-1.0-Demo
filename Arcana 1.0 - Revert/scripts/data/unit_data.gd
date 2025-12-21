extends Resource
class_name UnitData

@export var unit_class: UnitClass

@export var ai_profile: AIProfile = null
@export var level: int = 1
@export var exp: int = 0

# Per-unit permanent stat bonuses gained from level ups
@export var bonus_max_hp: int = 0
@export var bonus_atk: int = 0
@export var bonus_defense: int = 0
@export var bonus_move: int = 0
@export var bonus_max_mana: int = 0

# NEW: Arcana loadout for this specific unit.
# We keep it as plain Array to avoid type issues.
@export var equipped_arcana: Array = []    # will hold Skill resources

# NEW: per-unit equipment and items (2 slots each by design)
@export var equipment_slots: Array = []   # will hold Equipment resources
@export var item_slots: Array = []        # will hold Item resources
