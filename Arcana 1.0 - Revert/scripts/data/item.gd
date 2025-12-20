extends Resource
class_name Item

enum ItemType { CONSUMABLE, KEY }

@export var name: String = "Item"
@export_multiline var description: String = ""

@export var type: ItemType = ItemType.CONSUMABLE
@export var icon_texture: Texture2D 
# For now: simple heal / mana restore. We'll hook into battle later.
@export var restore_hp: int = 0
@export var restore_mana: int = 0
