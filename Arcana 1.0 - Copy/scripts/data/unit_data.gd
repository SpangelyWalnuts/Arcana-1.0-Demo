extends Resource
class_name UnitData

@export var unit_class: UnitClass

@export var level: int = 1
@export var exp: int = 0

# Per-unit permanent stat bonuses gained from level ups
@export var bonus_max_hp: int = 0
@export var bonus_atk: int = 0
@export var bonus_defense: int = 0
@export var bonus_move: int = 0
@export var bonus_max_mana: int = 0
