extends Control

@onready var floor_label: Label          = $Panel/VBoxContainer/FloorLabel
@onready var hint_label: Label           = $Panel/VBoxContainer/HintLabel
@onready var roster_list: ItemList       = $Panel/VBoxContainer/HBoxContainer/RosterBox/RosterList
@onready var deploy_list: ItemList       = $Panel/VBoxContainer/HBoxContainer/DeployBox/DeployList
@onready var start_button: Button        = $Panel/BottomBar/MarginContainer/HBoxContainer/StartBattleButton
@onready var title_button: Button        = $Panel/BottomBar/MarginContainer/HBoxContainer/ReturnToTitleButton
@onready var auto_place_button: Button = $Panel/BottomBar/MarginContainer/HBoxContainer/AutoPlaceButton
@onready var class_name_label: Label = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ClassNameLabel
@onready var stats_label: Label      = $Panel/VBoxContainer/HBoxContainer/DetailsBox/StatsLabel
@onready var mana_label: Label       = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ManaLabel
@onready var range_label: Label      = $Panel/VBoxContainer/HBoxContainer/DetailsBox/RangeLabel
@onready var arcana_label: Label     = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ArcanaLabel
@onready var level_label: Label      = $Panel/VBoxContainer/HBoxContainer/DetailsBox/LevelLabel

@onready var manage_arcana_button: Button = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ManageArcanaButton
@onready var arcana_popup: AcceptDialog   = $ArcanaPopup
@onready var arcana_list: VBoxContainer   = $ArcanaPopup/ArcanaList

@onready var equipment_label: Label        = $Panel/VBoxContainer/HBoxContainer/DetailsBox/EquipmentLabel
@onready var manage_equipment_button: Button = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ManageEquipmentButton
@onready var items_label: Label           = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ItemsLabel
@onready var manage_items_button: Button  = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ManageItemsButton

# NEW popups:
@onready var equipment_popup: AcceptDialog = $EquipmentPopup
@onready var equipment_list: VBoxContainer = $EquipmentPopup/EquipmentList
@onready var items_popup: AcceptDialog     = $ItemsPopup
@onready var items_list: VBoxContainer     = $ItemsPopup/ItemsList

#CONVOY + SHOP UI
@onready var right_tabs: TabContainer = $Panel/VBoxContainer/HBoxContainer/RightTabs

@onready var convoy_equip_list: ItemList = $Panel/VBoxContainer/HBoxContainer/RightTabs/ConvoyTab/MarginContainer/ConvoyRoot/ConvoyLists/ConvoyTabs/Equipment/VBoxContainer/ConvoyEquipmentList
@onready var convoy_item_list: ItemList = $Panel/VBoxContainer/HBoxContainer/RightTabs/ConvoyTab/MarginContainer/ConvoyRoot/ConvoyLists/ConvoyTabs/Items/VBoxContainer/ConvoyItemList

@onready var selected_unit_header: Label = $Panel/VBoxContainer/HBoxContainer/RightTabs/ConvoyTab/MarginContainer/ConvoyRoot/UnitLoadout/SelectedUnitHeader
@onready var equip_slots_grid: GridContainer = $Panel/VBoxContainer/HBoxContainer/RightTabs/ConvoyTab/MarginContainer/ConvoyRoot/UnitLoadout/EquipSlotsGrid
@onready var item_slots_grid: GridContainer = $Panel/VBoxContainer/HBoxContainer/RightTabs/ConvoyTab/MarginContainer/ConvoyRoot/UnitLoadout/ItemSlotsGrid
@onready var convoy_details_label: Label = $Panel/VBoxContainer/HBoxContainer/RightTabs/ConvoyTab/MarginContainer/ConvoyRoot/UnitLoadout/ConvoyDetailsLabel

@onready var shop_list_tab: ItemList = $Panel/VBoxContainer/HBoxContainer/RightTabs/ShopTab/MarginContainer/VBoxContainer/HBoxContainer/ShopList
@onready var shop_gold_label_tab: Label = $Panel/VBoxContainer/HBoxContainer/RightTabs/ShopTab/MarginContainer/VBoxContainer/ShopGoldLabel
@onready var shop_details_label_tab: Label = $Panel/VBoxContainer/HBoxContainer/RightTabs/ShopTab/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/ShopDetailsLabel
@onready var shop_buy_button_tab: Button = $Panel/VBoxContainer/HBoxContainer/RightTabs/ShopTab/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/ShopBuyButton

#MAP TETXURE
@onready var map_preview_texrect: TextureRect = $Panel/VBoxContainer/HBoxContainer/LeftPanel/VBoxContainer/PanelContainer/MapPreviewTexture
@onready var preview_terrain: TileMap = $PreviewMapRoot/PreviewTerrain
@onready var preview_map_gen: Node = $PreviewMapRoot/PreviewMapGenerator

#MAP TAGS
@onready var encounter_tag_label: Label = $EncounterTagLabel
@onready var weather_label: Label = $WeatherLabel

@onready var unit_name_label: Label = $Panel/VBoxContainer/HBoxContainer/DetailsBox/UnitNameLabel

# Track which unit is currently selected in the roster
var _selected_roster_index: int = -1

#MINIMAP VARS
var _placement_by_roster_index: Dictionary = {} # roster_index -> Vector2i
var _minimap_hover_cell: Vector2i = Vector2i(999999, 999999)
var _rmb_down_pos: Vector2 = Vector2.ZERO
var _rmb_dragged: bool = false

# Later we’ll hook this to map size / enemy count via some floor config.
@export var max_deploy_slots: int = 4

# Indices into RunManager.roster that are currently deployed
var _deployed_indices: Array[int] = []

#DEPLOYMENT PLACEMENT
var _minimap_used_rect: Rect2i = Rect2i()
var _minimap_scale: int = 16

var _minimap_view_origin: Vector2i = Vector2i.ZERO # top-left cell of the view window
var _minimap_view_size: Vector2i = Vector2i(32, 18) # how many tiles we show at once (tweak)

var _minimap_dragging: bool = false
var _minimap_drag_last_pos: Vector2 = Vector2.ZERO

# ------------------------------------------------------------
# Stage 2: Convoy + Shop Tab (MVP click-to-assign)
# ------------------------------------------------------------
var _selected_convoy_kind: StringName = &"none" # &"equipment" or &"item"
var _selected_convoy_res: Resource = null

# These arrays map ItemList index -> Resource key (stable)
var _convoy_equipment_key_cache: Array[Resource] = []
var _convoy_item_key_cache: Array[Resource] = []
var _shop_key_cache: Array[int] = [] # maps visible shop rows -> shop_stock index

func _ready() -> void:
	if not RunManager.run_active:
		RunManager.return_to_title()
		return
# Pull deploy limit from RunManager (scaled by floor/map)
	if RunManager.has_method("get_deploy_limit"):
		max_deploy_slots = RunManager.get_deploy_limit()

	floor_label.text = "Floor %d" % RunManager.current_floor
	hint_label.text = "Select up to %d units to deploy." % max_deploy_slots

	if RunManager.has_method("ensure_floor_config"):
		RunManager.ensure_floor_config()
	
	_preview_generate_map()
# Only auto-generate deploy tiles if they aren't already set
	RunManager.ensure_floor_config()
	if RunManager.deploy_tiles.is_empty():
		RunManager.deploy_tiles = _compute_deploy_tiles_from_map(preview_terrain, max_deploy_slots)
		print("[DEPLOY] computed tiles=", RunManager.deploy_tiles)
		_placement_by_roster_index.clear()
	_minimap_center_on_deploy()
	_build_static_minimap_from_tilemap(preview_terrain)
	deploy_list.item_selected.connect(func(_i):
		_update_minimap_hint_label()
		_build_static_minimap_from_tilemap(preview_terrain)
)
	print("[MINIMAP] used_rect=", preview_terrain.get_used_rect())
	_populate_roster_lists()
	_update_encounter_tag_ui()
	_update_weather_ui()

	# Double-click to move units between lists
	roster_list.item_activated.connect(_on_roster_item_activated)
	deploy_list.item_activated.connect(_on_deploy_item_activated)

	# Single-click to show details
	roster_list.item_selected.connect(_on_roster_item_selected)

	start_button.pressed.connect(_on_start_battle_pressed)
	title_button.pressed.connect(_on_return_to_title_pressed)
	manage_arcana_button.pressed.connect(_on_manage_arcana_pressed)
	arcana_popup.confirmed.connect(_on_arcana_popup_confirmed)
	auto_place_button.pressed.connect(_auto_place_deployed_units)

	manage_equipment_button.pressed.connect(_on_manage_equipment_pressed)
	manage_items_button.pressed.connect(_on_manage_items_pressed)

	equipment_popup.confirmed.connect(_on_equipment_popup_confirmed)
	items_popup.confirmed.connect(_on_items_popup_confirmed)

	map_preview_texrect.gui_input.connect(_on_minimap_gui_input)

	# Convoy selection
	convoy_equip_list.item_selected.connect(_on_convoy_equipment_selected)
	convoy_item_list.item_selected.connect(_on_convoy_item_selected)

	# Unit selection updates slots
	
	deploy_list.item_clicked.connect(func(_i, _pos, _btn): call_deferred("_refresh_selected_unit_slots"))
	right_tabs.tab_changed.connect(func(_idx): call_deferred("_refresh_selected_unit_slots"))

	deploy_list.item_selected.connect(func(i: int) -> void:
		call_deferred("_refresh_selected_unit_slots")
		if i >= 0 and i < _deployed_indices.size():
			_selected_roster_index = _deployed_indices[i]
			_show_unit_details_from_roster_index(_selected_roster_index)
)


	# Shop tab
	shop_list_tab.item_selected.connect(_on_shop_selected)
	shop_buy_button_tab.pressed.connect(_on_shop_buy_pressed)


	_refresh_convoy_ui()
	_refresh_shop_tab_ui()
	_refresh_selected_unit_slots()


	_clear_details_panel()

#HANDLERS
func _on_roster_item_selected(index: int) -> void:
	_selected_roster_index = index
	_show_unit_details_from_roster_index(index)


func _show_unit_details_from_roster_index(roster_index: int) -> void:
	var roster = RunManager.roster
	if roster_index < 0 or roster_index >= roster.size():
		_clear_details_panel()
		return

	var data: UnitData = roster[roster_index]
	if data == null or data.unit_class == null:
		_clear_details_panel()
		return

	var cls: UnitClass = data.unit_class

	# --- Base stats from class ---
	var base_max_hp: int    = cls.max_hp
	var base_atk: int       = cls.atk
	var base_def: int       = cls.defense
	var base_move: int      = cls.move_range
	var base_max_mana: int  = cls.max_mana
	var base_attack_range: int = cls.attack_range

	# --- Add permanent per-unit bonuses (from level-ups etc.) ---
	var total_max_hp: int   = base_max_hp    + data.bonus_max_hp
	var total_atk: int      = base_atk       + data.bonus_atk
	var total_def: int      = base_def       + data.bonus_defense
	var total_move: int     = base_move      + data.bonus_move
	var total_max_mana: int = base_max_mana  + data.bonus_max_mana
	var total_attack_range: int = base_attack_range

	# --- Add equipment bonuses ---
	for eq in data.equipment_slots:
		if eq == null:
			continue
		var e: Equipment = eq as Equipment
		if e == null:
			continue

		total_max_hp    += e.bonus_max_hp
		total_atk       += e.bonus_atk
		total_def       += e.bonus_defense
		total_move      += e.bonus_move
		total_max_mana  += e.bonus_max_mana
		# (you could also let equipment modify attack_range later if you want)

	# --- UI: Name / Class / Level ---
	if unit_name_label:
		# Right now we don't have a custom per-unit name field,
		# so we'll just use the class display name as the "name".
		unit_name_label.text = "Name: %s" % cls.display_name

	class_name_label.text = "Class: %s" % cls.display_name
	level_label.text      = "Level: %d   EXP: %d" % [data.level, data.exp]

	# --- UI: Stats ---
	stats_label.text = "HP: %d   ATK: %d   DEF: %d" % [
		total_max_hp,
		total_atk,
		total_def
	]

	mana_label.text = "Mana: %d (Regen: %d/turn)" % [
		total_max_mana,
		cls.mana_regen_per_turn
	]

	range_label.text = "Move: %d   Range: %d" % [
		total_move,
		total_attack_range
	]

	# --- Arcana (equipped) ---
	if data.equipped_arcana.size() == 0:
		arcana_label.text = "Arcana: (none equipped)"
	else:
		var arc_names: Array[String] = []
		for s in data.equipped_arcana:
			if s != null:
				arc_names.append(s.name)
		arcana_label.text = "Arcana: " + ", ".join(arc_names)

	# --- Equipment slots ---
		# --- Equipment slots ---
	if data.equipment_slots.size() == 0:
		equipment_label.text = "Equipment: (none)"
	else:
		var lines: Array[String] = []
		lines.append("Equipment:")

		for eqr in data.equipment_slots:
			if eqr == null:
				continue
			var eq: Equipment = eqr as Equipment
			if eq == null:
				continue

			lines.append("- " + eq.name)

			var fx: String = _equipment_effect_text(eq)
			if fx != "":
				# indent effect lines a bit for readability
				for l in fx.split("\n"):
					lines.append("   " + l)

		equipment_label.text = "\n".join(lines)

	# --- Item slots ---
	if data.item_slots.size() == 0:
		items_label.text = "Items: (none)"
	else:
		var item_names: Array[String] = []
		for it in data.item_slots:
			if it != null:
				item_names.append(it.name)
		items_label.text = "Items: " + ", ".join(item_names)

#CONVOY HELPERS
func _resource_sort_key(a: Resource, b: Resource) -> bool:
	var an: String = ""
	var bn: String = ""
	if a != null and ("name" in a):
		an = str(a.name)
	if b != null and ("name" in b):
		bn = str(b.name)
	return an.naturalcasecmp_to(bn) < 0

func _ensure_unit_slot_arrays(data: UnitData) -> void:
	if data == null:
		return

	# 2 slots each by design
	while data.equipment_slots.size() < 2:
		data.equipment_slots.append(null)
	while data.item_slots.size() < 2:
		data.item_slots.append(null)

func _inv_add_one(inv: Dictionary, res: Resource) -> void:
	if res == null:
		return
	var c: int = int(inv.get(res, 0))
	inv[res] = c + 1


func _inv_take_one(inv: Dictionary, res: Resource) -> bool:
	if res == null:
		return false
	if not inv.has(res):
		return false
	var c: int = int(inv[res])
	if c <= 0:
		return false
	if c == 1:
		inv.erase(res)
	else:
		inv[res] = c - 1
	return true


#USAGE HELPERS
func _count_equipment_usage(eq: Equipment, exclude_roster_index: int) -> int:
	var count := 0

	for i in range(RunManager.roster.size()):
		if i == exclude_roster_index:
			continue

		var data: UnitData = RunManager.roster[i]
		if data == null:
			continue

		for slot in data.equipment_slots:
			if slot == eq:
				count += 1

	return count

func _get_selected_deployed_roster_index() -> int:
	var sel := deploy_list.get_selected_items()
	if sel.is_empty():
		return -1
	var deploy_pos: int = sel[0]
	if deploy_pos < 0 or deploy_pos >= _deployed_indices.size():
		return -1
	return _deployed_indices[deploy_pos]

func _refresh_details_for_selected_deploy() -> void:
	var r_idx := _get_selected_deployed_roster_index()
	if r_idx >= 0:
		_show_unit_details_from_roster_index(r_idx)

func _count_item_usage(item: Item, exclude_roster_index: int) -> int:
	var count := 0

	for i in range(RunManager.roster.size()):
		if i == exclude_roster_index:
			continue

		var data: UnitData = RunManager.roster[i]
		if data == null:
			continue

		for slot in data.item_slots:
			if slot == item:
				count += 1

	return count

#CLEAR DETAILS HELPER 
func _clear_details_panel() -> void:
	_selected_roster_index = -1

	if unit_name_label:
		unit_name_label.text = "Name: -"

	class_name_label.text = "Class: -"
	level_label.text      = "Level: -   EXP: -"
	stats_label.text      = "HP: -   ATK: -   DEF: -"
	mana_label.text       = "Mana: -"
	range_label.text      = "Move: -   Range: -"
	arcana_label.text     = "Arcana: -"
	equipment_label.text  = "Equipment: -"
	items_label.text      = "Items: -"





func _populate_roster_lists() -> void:
	roster_list.clear()
	deploy_list.clear()
	_deployed_indices.clear()

	var roster = RunManager.roster

	for i in range(roster.size()):
		var data: UnitData = roster[i]
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		var label_text := "%s (Lv %d)" % [cls.display_name, data.level]

		# Add item first
		var item_index: int = roster_list.get_item_count()
		roster_list.add_item(label_text)

		# Then set icon if class has a portrait/icon texture
		if cls.portrait_texture != null:
			roster_list.set_item_icon(item_index, cls.portrait_texture)




func _on_roster_item_activated(index: int) -> void:
	# Move from roster → deploy if we have room
	if _deployed_indices.size() >= max_deploy_slots:
		return

	if _deployed_indices.has(index):
		return

	_deployed_indices.append(index)
	_refresh_lists()


func _on_deploy_item_activated(index: int) -> void:
	# index here is position in deploy_list, not roster index
	if index < 0 or index >= _deployed_indices.size():
		return
	var roster_index := _deployed_indices[index]
	_placement_by_roster_index.erase(roster_index)
	_deployed_indices.remove_at(index)
	_refresh_lists()


func _refresh_lists() -> void:
	roster_list.clear()
	deploy_list.clear()

	var roster = RunManager.roster

	# --- Rebuild roster list ---
	for i in range(roster.size()):
		var data: UnitData = roster[i]
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		var text := "%s (Lv %d)" % [cls.display_name, data.level]

		if _deployed_indices.has(i):
			text += " [DEPLOYED]"

		var item_index: int = roster_list.get_item_count()
		roster_list.add_item(text)

		if cls.portrait_texture != null:
			roster_list.set_item_icon(item_index, cls.portrait_texture)

	# --- Rebuild deployed list in the same order as _deployed_indices ---
	for roster_index in _deployed_indices:
		if roster_index < 0 or roster_index >= roster.size():
			continue

		var data: UnitData = roster[roster_index]
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		var text := "%s (Lv %d)" % [cls.display_name, data.level]

		var item_index: int = deploy_list.get_item_count()
		deploy_list.add_item(text)

		if cls.portrait_texture != null:
			deploy_list.set_item_icon(item_index, cls.portrait_texture)
	call_deferred("_refresh_selected_unit_slots")



func _on_start_battle_pressed() -> void:
	if _deployed_indices.is_empty():
		return

	var roster = RunManager.roster

	RunManager.deployed_units.clear()
	RunManager.deployed_positions.clear() # <-- you must add this var in RunManager.gd

	# Optional: require placement for all deployed units (Fire Emblem style)
	for idx in _deployed_indices:
		if not _placement_by_roster_index.has(idx):
			hint_label.text = "Place all deployed units before starting."
			return

	for idx in _deployed_indices:
		if idx < 0 or idx >= roster.size():
			continue

		var data: UnitData = roster[idx]
		if data == null:
			continue

		RunManager.deployed_units.append(data)

		# Pull the placed cell
		var cell: Vector2i = _placement_by_roster_index[idx]
		RunManager.deployed_positions.append(cell)

	# Go to battle scene
	RunManager.goto_battle_scene()


func _on_return_to_title_pressed() -> void:
	RunManager.return_to_title()

#MANAGE ARCANA
func _on_manage_arcana_pressed() -> void:
	if _selected_roster_index < 0:
		return

	var roster = RunManager.roster
	if _selected_roster_index >= roster.size():
		return

	var data: UnitData = roster[_selected_roster_index]
	if data == null or data.unit_class == null:
		return

	var cls: UnitClass = data.unit_class

	# Clear old options
	for child in arcana_list.get_children():
		child.queue_free()

	# Build one CheckBox per available arcana (from class.skills)
	for s in cls.skills:
		if s == null:
			continue
		var cb := CheckBox.new()
		cb.text = s.name
		cb.set_meta("skill", s)
		# pre-check if currently equipped
		if data.equipped_arcana.has(s):
			cb.button_pressed = true
		arcana_list.add_child(cb)

	arcana_popup.title = "Select Arcana (up to 3)"
	arcana_popup.popup_centered()


func _on_arcana_popup_confirmed() -> void:
	if _selected_roster_index < 0:
		return

	var roster = RunManager.roster
	if _selected_roster_index >= roster.size():
		return

	var data: UnitData = roster[_selected_roster_index]
	if data == null or data.unit_class == null:
		return

	var selected: Array = []
	for child in arcana_list.get_children():
		if child is CheckBox:
			var cb: CheckBox = child
			if cb.button_pressed and cb.has_meta("skill"):
				var skill = cb.get_meta("skill")
				if skill != null:
					selected.append(skill)

	# Limit to 3
	if selected.size() > 3:
		selected = selected.slice(0, 3)

	data.equipped_arcana = selected

	# Refresh details panel so UI matches new loadout
	_show_unit_details_from_roster_index(_selected_roster_index)

# EQUIPMENT HELPERS

func _on_manage_equipment_pressed() -> void:
	if _selected_roster_index < 0:
		return

	var roster = RunManager.roster
	if _selected_roster_index >= roster.size():
		return

	var data: UnitData = roster[_selected_roster_index]
	if data == null:
		return

	# Clear old checkboxes
	for child in equipment_list.get_children():
		child.queue_free()

	# Build checkboxes from RunManager.equipment_defs using inventory counts
	for eq in RunManager.equipment_defs:
		if eq == null:
			continue

		var owned: int = 0
		if RunManager.inventory_equipment.has(eq):
			owned = int(RunManager.inventory_equipment[eq])

		# How many copies are already used by *other* units
		var used_by_others: int = _count_equipment_usage(eq, _selected_roster_index)

		# Already equipped on this unit
		var already_equipped: int = 0
		for slot in data.equipment_slots:
			if slot == eq:
				already_equipped += 1

		# Remaining copies available to equip here
		var remaining_for_this_unit: int = owned - used_by_others

		var cb := CheckBox.new()

		# Label shows name and stock info
		cb.text = "%s (%d/%d)" % [eq.name, owned - used_by_others, owned]

		var fx_text: String = _equipment_effect_text(eq)
		if fx_text != "":
			cb.tooltip_text = fx_text

		cb.set_meta("equipment", eq)


		# Pre-check if this unit already has it equipped
		if already_equipped > 0:
			cb.button_pressed = true

		# If no remaining copies and not already equipped, disable it
		if remaining_for_this_unit <= 0 and already_equipped == 0:
			cb.disabled = true

		equipment_list.add_child(cb)

	equipment_popup.title = "Select Equipment (max 2)"
	equipment_popup.popup_centered()



func _on_equipment_popup_confirmed() -> void:
	if _selected_roster_index < 0:
		return

	var roster = RunManager.roster
	if _selected_roster_index >= roster.size():
		return

	var data: UnitData = roster[_selected_roster_index]
	if data == null:
		return

	var selected: Array = []

	# First, gather requested equipment from the UI
	for child in equipment_list.get_children():
		if child is CheckBox:
			var cb: CheckBox = child
			if cb.button_pressed and cb.has_meta("equipment"):
				var eq = cb.get_meta("equipment")
				if eq != null:
					selected.append(eq)

	# Enforce slot limit: 2 equipment max
	if selected.size() > 2:
		selected = selected.slice(0, 2)

	# Extra safety: enforce quantity vs inventory
	var final_selected: Array = []
	var temp_usage: Dictionary = {}

	for eq in selected:
		if eq == null:
			continue

		var owned: int = 0
		if RunManager.inventory_equipment.has(eq):
			owned = int(RunManager.inventory_equipment[eq])

		# Usage by others
		var used_by_others: int = _count_equipment_usage(eq, _selected_roster_index)

		# Already chosen in this confirmation pass
		var used_here: int = int(temp_usage.get(eq, 0))

		if used_by_others + used_here < owned:
			final_selected.append(eq)
			temp_usage[eq] = used_here + 1
		else:
			# No remaining copies, skip
			pass

	data.equipment_slots = final_selected

	_show_unit_details_from_roster_index(_selected_roster_index)


# ITEM POPUP HELPER
func _on_manage_items_pressed() -> void:
	if _selected_roster_index < 0:
		return

	var roster = RunManager.roster
	if _selected_roster_index >= roster.size():
		return

	var data: UnitData = roster[_selected_roster_index]
	if data == null:
		return

	# Clear old
	for child in items_list.get_children():
		child.queue_free()

	for it in RunManager.item_defs:
		if it == null:
			continue

		var owned: int = 0
		if RunManager.inventory_items.has(it):
			owned = int(RunManager.inventory_items[it])

		var used_by_others: int = _count_item_usage(it, _selected_roster_index)

		var already_equipped: int = 0
		for slot in data.item_slots:
			if slot == it:
				already_equipped += 1

		var remaining_for_this_unit: int = owned - used_by_others

		var cb := CheckBox.new()
		cb.text = "%s (%d/%d)" % [it.name, owned - used_by_others, owned]
		cb.set_meta("item", it)

		if already_equipped > 0:
			cb.button_pressed = true

		if remaining_for_this_unit <= 0 and already_equipped == 0:
			cb.disabled = true

		items_list.add_child(cb)

	items_popup.title = "Select Items (max 2)"
	items_popup.popup_centered()



func _on_items_popup_confirmed() -> void:
	if _selected_roster_index < 0:
		return

	var roster = RunManager.roster
	if _selected_roster_index >= roster.size():
		return

	var data: UnitData = roster[_selected_roster_index]
	if data == null:
		return

	var selected: Array = []

	for child in items_list.get_children():
		if child is CheckBox:
			var cb: CheckBox = child
			if cb.button_pressed and cb.has_meta("item"):
				var it = cb.get_meta("item")
				if it != null:
					selected.append(it)

	# Slot limit: 2 items
	if selected.size() > 2:
		selected = selected.slice(0, 2)

	# Quantity safety
	var final_selected: Array = []
	var temp_usage: Dictionary = {}

	for it in selected:
		if it == null:
			continue

		var owned: int = 0
		if RunManager.inventory_items.has(it):
			owned = int(RunManager.inventory_items[it])

		var used_by_others: int = _count_item_usage(it, _selected_roster_index)
		var used_here: int = int(temp_usage.get(it, 0))

		if used_by_others + used_here < owned:
			final_selected.append(it)
			temp_usage[it] = used_here + 1
		else:
			# No remaining copies, skip
			pass

	data.item_slots = final_selected

	_show_unit_details_from_roster_index(_selected_roster_index)
func _shop_get_icon(res: Resource) -> Texture2D:
	if res == null:
		return null

	# Common conventions across your resources
	if "icon_texture" in res and res.icon_texture != null:
		return res.icon_texture
	if "icon" in res and res.icon != null:
		return res.icon
	if "texture" in res and res.texture != null:
		return res.texture
	if "portrait_texture" in res and res.portrait_texture != null:
		return res.portrait_texture

	return null


func _shop_get_rarity_label(res: Resource) -> String:
	if res == null:
		return "Common"

	var path: String = ""
	if "resource_path" in res:
		path = String(res.resource_path).to_lower()

	# Folder-based rarity (matches how you organized equipment)
	if path.find("/legendary/") != -1:
		return "Legendary"
	if path.find("/rare/") != -1:
		return "Rare"
	if path.find("/uncommon/") != -1:
		return "Uncommon"

	return "Common"


func _shop_entry_name(res: Resource) -> String:
	if res == null:
		return "Unknown"
	if "name" in res:
		return String(res.name)
	return "Unknown"


func _shop_entry_desc(res: Resource) -> String:
	if res == null:
		return ""
	if "description" in res:
		return String(res.description)
	return ""

func _equipment_effect_lines(eq: Equipment) -> Array[String]:
	var lines: Array[String] = []
	if eq == null:
		return lines

	# Immunity: all negative statuses
	if "immune_negative_statuses" in eq and bool(eq.immune_negative_statuses):
		lines.append("• Immune to negative statuses")

	# Immunity: specific status keys
	if "immune_status_keys" in eq:
		var keys = eq.immune_status_keys
		if typeof(keys) == TYPE_ARRAY and not keys.is_empty():
			var key_names: Array[String] = []
			for k in keys:
				key_names.append(String(k))
			lines.append("• Immune: " + ", ".join(key_names))

	# Duration bonus applied
	if "bonus_status_duration_applied" in eq:
		var b: int = int(eq.bonus_status_duration_applied)
		if b != 0:
			var sign := "+" if b > 0 else ""
			lines.append("• Statuses you apply last %s%d turn(s)" % [sign, b])

	return lines


func _equipment_effect_text(eq: Equipment) -> String:
	var lines := _equipment_effect_lines(eq)
	if lines.is_empty():
		return ""
	return "\n".join(lines)

#Buy Handler
func _on_shop_buy_pressed() -> void:
	var sel := shop_list_tab.get_selected_items()
	if sel.is_empty():
		return

	var visible_index: int = sel[0]
	if visible_index < 0 or visible_index >= _shop_key_cache.size():
		return

	var stock_index: int = _shop_key_cache[visible_index]
	var result: Dictionary = RunManager.try_buy_from_shop(stock_index)

	if not bool(result.get("success", false)):
		shop_details_label_tab.text = str(result.get("reason", "Purchase failed."))
		return

	_refresh_shop_tab_ui()
	_refresh_convoy_ui()

#ENCOUNTER TAG HELPER
func _update_encounter_tag_ui() -> void:
	if encounter_tag_label == null:
		return

	var tag: StringName = &"none"
	# Prefer accessor if you added it, otherwise read the variable directly.
	if RunManager.has_method("get_encounter_tag"):
		tag = RunManager.get_encounter_tag()
	elif "current_encounter_tag" in RunManager:
		tag = RunManager.current_encounter_tag

	match tag:
		&"swarm":
			encounter_tag_label.text = "Encounter: Swarm"
			encounter_tag_label.visible = true
		&"elite_guard":
			encounter_tag_label.text = "Encounter: Elite Guard"
			encounter_tag_label.visible = true
		&"caster_heavy":
			encounter_tag_label.text = "Encounter: Caster Heavy"
			encounter_tag_label.visible = true
		_:
			# Covers &"none" and anything unknown
			encounter_tag_label.visible = false

#WEATHER HELPER 
func _update_weather_ui() -> void:
	if weather_label == null:
		return

	var w: StringName = &"clear"
	if RunManager.has_method("get_weather"):
		w = RunManager.get_weather()
	elif "current_weather" in RunManager:
		w = RunManager.current_weather

	match w:
		&"snow":
			weather_label.text = "Weather: Snow"
			weather_label.visible = true
		_:
			weather_label.text = "Weather: Clear"
			weather_label.visible = true

func _refresh_convoy_ui() -> void:
	# Equipment
	convoy_equip_list.clear()
	_convoy_equipment_key_cache.clear()

	var equip_keys: Array = RunManager.inventory_equipment.keys()
	equip_keys.sort_custom(Callable(self, "_resource_sort_key"))

	for k in equip_keys:
		var res: Resource = k
		var count: int = int(RunManager.inventory_equipment.get(res, 0))
		var label: String = "Equipment"
		if res != null and ("name" in res):
			label = str(res.name)
		convoy_equip_list.add_item("%s  x%d" % [label, count])
		_convoy_equipment_key_cache.append(res)

	# Items
	convoy_item_list.clear()
	_convoy_item_key_cache.clear()

	var item_keys: Array = RunManager.inventory_items.keys()
	item_keys.sort_custom(Callable(self, "_resource_sort_key"))

	for k2 in item_keys:
		var res2: Resource = k2
		var count2: int = int(RunManager.inventory_items.get(res2, 0))
		var label2: String = "Item"
		if res2 != null and ("name" in res2):
			label2 = str(res2.name)
		convoy_item_list.add_item("%s  x%d" % [label2, count2])
		_convoy_item_key_cache.append(res2)


func _on_convoy_equipment_selected(index: int) -> void:
	_selected_convoy_kind = &"equipment"
	_selected_convoy_res = null

	if index < 0 or index >= _convoy_equipment_key_cache.size():
		convoy_details_label.text = ""
		return

	_selected_convoy_res = _convoy_equipment_key_cache[index]
	var e: Resource = _selected_convoy_res
	var n: String = str(e.name) if e != null and ("name" in e) else "Equipment"
	var d: String = str(e.description) if e != null and ("description" in e) else ""
	convoy_details_label.text = "%s\n\n%s" % [n, d]


func _on_convoy_item_selected(index: int) -> void:
	_selected_convoy_kind = &"item"
	_selected_convoy_res = null

	if index < 0 or index >= _convoy_item_key_cache.size():
		convoy_details_label.text = ""
		return

	_selected_convoy_res = _convoy_item_key_cache[index]
	var it: Resource = _selected_convoy_res
	var n: String = str(it.name) if it != null and ("name" in it) else "Item"
	var d: String = str(it.description) if it != null and ("description" in it) else ""
	convoy_details_label.text = "%s\n\n%s" % [n, d]

func _get_selected_unit_data() -> UnitData:
	var sel := deploy_list.get_selected_items()
	if sel.is_empty():
		return null

	var deploy_pos: int = sel[0]
	if deploy_pos < 0 or deploy_pos >= _deployed_indices.size():
		return null

	var roster_index: int = _deployed_indices[deploy_pos]
	if roster_index < 0 or roster_index >= RunManager.roster.size():
		return null

	return RunManager.roster[roster_index]


func _refresh_selected_unit_slots() -> void:
	# Clear existing slot buttons
	for c in equip_slots_grid.get_children():
		c.queue_free()
	for c2 in item_slots_grid.get_children():
		c2.queue_free()

	var data: UnitData = _get_selected_unit_data()
	if data == null:
		selected_unit_header.text = "Selected Unit"
		return
	
	_ensure_unit_slot_arrays(data)
	
	var title: String = "Selected Unit"
	if data.unit_class != null and ("display_name" in data.unit_class):
		title = "Selected: %s" % str(data.unit_class.display_name)
	selected_unit_header.text = title

	# Equipment slots
	for i in range(data.equipment_slots.size()):
		var b := Button.new()
		var res = data.equipment_slots[i]
		b.text = (str(res.name) if res != null and ("name" in res) else "Empty Equip")
		b.pressed.connect(_on_equip_slot_pressed.bind(i))
		equip_slots_grid.add_child(b)

	# Item slots
	for j in range(data.item_slots.size()):
		var b2 := Button.new()
		var res2 = data.item_slots[j]
		b2.text = (str(res2.name) if res2 != null and ("name" in res2) else "Empty Item")
		b2.pressed.connect(_on_item_slot_pressed.bind(j))
		item_slots_grid.add_child(b2)

func _refresh_shop_tab_ui() -> void:
	shop_list_tab.clear()
	_shop_key_cache.clear()

	shop_gold_label_tab.text = "Gold: %d" % RunManager.gold

	for i in range(RunManager.shop_stock.size()):
		var entry: Dictionary = RunManager.shop_stock[i]
		var stock: int = int(entry.get("stock", 0))
		if stock <= 0:
			continue

		var res: Resource = entry.get("resource", null)
		var price: int = int(entry.get("price", 0))

		var name: String = "???"
		if res != null and ("name" in res):
			name = str(res.name)

		shop_list_tab.add_item("%s  (%dG)  x%d" % [name, price, stock])
		_shop_key_cache.append(i)


func _on_shop_selected(index: int) -> void:
	if index < 0 or index >= _shop_key_cache.size():
		shop_details_label_tab.text = ""
		return

	var stock_index: int = _shop_key_cache[index]
	var entry: Dictionary = RunManager.shop_stock[stock_index]
	var res: Resource = entry.get("resource", null)
	var price: int = int(entry.get("price", 0))
	var stock: int = int(entry.get("stock", 0))

	if res == null:
		shop_details_label_tab.text = ""
		return

	var n: String = str(res.name) if ("name" in res) else "???"
	var d: String = str(res.description) if ("description" in res) else ""
	shop_details_label_tab.text = "%s\nPrice: %dG\nStock: %d\n\n%s" % [n, price, stock, d]

func _on_equip_slot_pressed(slot_idx: int) -> void:
	var data: UnitData = _get_selected_unit_data()
	if data == null:
		return
	_ensure_unit_slot_arrays(data)
	# If nothing selected in convoy: unequip to convoy
	if _selected_convoy_kind == &"none" or _selected_convoy_res == null:
		var current = data.equipment_slots[slot_idx]
		if current != null:
			_inv_add_one(RunManager.inventory_equipment, current)
			data.equipment_slots[slot_idx] = null
			_refresh_convoy_ui()
			_refresh_selected_unit_slots()
			_refresh_details_for_selected_deploy()
		return

	if _selected_convoy_kind != &"equipment":
		return

	if _inv_take_one(RunManager.inventory_equipment, _selected_convoy_res):
		data.equipment_slots[slot_idx] = _selected_convoy_res

	_selected_convoy_kind = &"none"
	_selected_convoy_res = null
	_refresh_convoy_ui()
	_refresh_selected_unit_slots()
	convoy_equip_list.deselect_all()
	convoy_item_list.deselect_all()
	_refresh_details_for_selected_deploy()

func _on_item_slot_pressed(slot_idx: int) -> void:
	var data: UnitData = _get_selected_unit_data()
	if data == null:
		return
	_ensure_unit_slot_arrays(data)
	# Unequip to convoy
	if _selected_convoy_kind == &"none" or _selected_convoy_res == null:
		var current = data.item_slots[slot_idx]
		if current != null:
			_inv_add_one(RunManager.inventory_items, current)
			data.item_slots[slot_idx] = null
			_refresh_convoy_ui()
			_refresh_selected_unit_slots()
			_refresh_details_for_selected_deploy()
		return

	if _selected_convoy_kind != &"item":
		return

	if _inv_take_one(RunManager.inventory_items, _selected_convoy_res):
		data.item_slots[slot_idx] = _selected_convoy_res

	_selected_convoy_kind = &"none"
	_selected_convoy_res = null
	_refresh_convoy_ui()
	_refresh_selected_unit_slots()
	_refresh_details_for_selected_deploy()

#MINIMAP TEXTURE BUILD
func _build_static_minimap_from_tilemap(tilemap: TileMap) -> void:
	if tilemap == null or map_preview_texrect == null:
		return

	var used: Rect2i = tilemap.get_used_rect()
	if used.size == Vector2i.ZERO:
		map_preview_texrect.texture = null
		return

	_minimap_used_rect = used

	# Clamp view size (can't be bigger than map)
	var view_w: int = min(_minimap_view_size.x, used.size.x)
	var view_h: int = min(_minimap_view_size.y, used.size.y)
	var view_size := Vector2i(view_w, view_h)

	# Clamp view origin so window stays within used rect
	var max_origin: Vector2i = used.position + used.size - view_size
	_minimap_view_origin.x = clamp(_minimap_view_origin.x, used.position.x, max_origin.x)
	_minimap_view_origin.y = clamp(_minimap_view_origin.y, used.position.y, max_origin.y)

	# Fixed-size image: view window * px-per-tile
	var img_w: int = view_size.x * _minimap_scale
	var img_h: int = view_size.y * _minimap_scale

	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# --- BASE MAP ---
	for vy in range(view_size.y):
		for vx in range(view_size.x):
			var cell: Vector2i = _minimap_view_origin + Vector2i(vx, vy)
			var source_id: int = tilemap.get_cell_source_id(0, cell)
			if source_id == -1:
				continue

			var td: TileData = tilemap.get_cell_tile_data(0, cell)
			if td == null:
				continue

			var v = td.get_custom_data("minimap_type")
			if v == null:
				continue # hide untagged tiles (reduces noise)

			var t: String = str(v)
			var c: Color = _minimap_color_for_type(t)

			_minimap_draw_tile_rect(img, vx, vy, _minimap_scale, c)

	# --- OVERLAYS ---
	_draw_minimap_overlays(img, tilemap, view_size)

	map_preview_texrect.texture = ImageTexture.create_from_image(img)

func _preview_generate_map() -> void:
	if preview_map_gen == null:
		push_warning("Preview map generator missing.")
		return

	# Match floor config just like Main does
	if preview_map_gen.has_method("set_biome"):
		preview_map_gen.set_biome(RunManager.current_biome)
	elif "biome" in preview_map_gen:
		preview_map_gen.biome = RunManager.current_biome

	if "chunks_wide" in preview_map_gen and "chunks_high" in preview_map_gen:
		preview_map_gen.chunks_wide = RunManager.current_map_chunks.x
		preview_map_gen.chunks_high = RunManager.current_map_chunks.y

	# Deterministic seed (make sure RunManager.current_map_seed exists)
	if preview_map_gen.has_method("set_seed"):
		preview_map_gen.set_seed(RunManager.current_map_seed)

	# Build map into PreviewTerrain (assigned via exported 'terrain' in inspector)
	if preview_map_gen.has_method("build_random_map"):
		preview_map_gen.build_random_map()
	else:
		push_warning("Preview map generator has no build_random_map().")

func _rebuild_minimap_deferred() -> void:
	_build_static_minimap_from_tilemap(preview_terrain)

func _minimap_draw_dot(img: Image, px: int, py: int, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx*dx + dy*dy > r*r:
				continue
			var x := px + dx
			var y := py + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var base := img.get_pixel(x, y)
			img.set_pixel(x, y, base.lerp(col, col.a))

#PALETTE HELPER MINIMAP
func _minimap_color_for_type(t: String) -> Color:
	match t:
		"water":
			return Color(0.20, 0.35, 0.75, 1.0)
		"ground":
			return Color(0.75, 0.75, 0.78, 1.0)
		"road":
			return Color(0.78, 0.70, 0.50, 1.0)
		"forest":
			return Color(0.22, 0.55, 0.28, 1.0)
		"mountain":
			return Color(0.45, 0.42, 0.40, 1.0)
		"wall":
			return Color(0.25, 0.25, 0.28, 1.0)
		"building":
			return Color(0.55, 0.50, 0.48, 1.0)
		"snow":
			return Color(0.88, 0.90, 0.95, 1.0)
		_:
			# Fallback if untagged
			return Color(0.72, 0.72, 0.75, 1.0)

func _get_preview_deploy_tiles() -> Array[Vector2i]:
	RunManager.ensure_floor_config()
	return RunManager.deploy_tiles

func _minimap_draw_tile_rect(img: Image, local_x: int, local_y: int, scale: int, col: Color) -> void:
	var px0 := local_x * scale
	var py0 := local_y * scale
	for py in range(py0, py0 + scale):
		for px in range(px0, px0 + scale):
			var base := img.get_pixel(px, py)
			img.set_pixel(px, py, base.lerp(col, col.a))

func _minimap_is_walkable(tilemap: TileMap, cell: Vector2i) -> bool:
	if tilemap.get_cell_source_id(0, cell) == -1:
		return false

	var td: TileData = tilemap.get_cell_tile_data(0, cell)
	if td == null:
		return false

	var v = td.get_custom_data("minimap_type")
	if v == null:
		return false

	var t := str(v)
	return (t == "ground" or t == "road" or t == "forest" or t == "snow" or t == "building")

	
func _min_distance_to_tiles(cell: Vector2i, tiles: Array[Vector2i]) -> int:
	var best: int = 999999
	for d: Vector2i in tiles:
		var md: int = abs(cell.x - d.x) + abs(cell.y - d.y)
		if md < best:
			best = md
	return best

#CLICK TO DEPLOY HELPER
func _minimap_local_pos_to_cell(local_pos: Vector2) -> Vector2i:
	if _minimap_scale <= 0 or _minimap_used_rect.size == Vector2i.ZERO:
		return Vector2i(999999, 999999)

	var tex := map_preview_texrect.texture
	if tex == null:
		return Vector2i(999999, 999999)

	var tex_size: Vector2 = tex.get_size()
	var rect_size: Vector2 = map_preview_texrect.size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return Vector2i(999999, 999999)

	# Map click from control pixels -> texture pixels
	var u: float = local_pos.x / rect_size.x
	var v: float = local_pos.y / rect_size.y
	if u < 0.0 or v < 0.0 or u > 1.0 or v > 1.0:
		return Vector2i(999999, 999999)

	var tex_x: float = u * tex_size.x
	var tex_y: float = v * tex_size.y

	var vx: int = int(floor(tex_x / float(_minimap_scale)))
	var vy: int = int(floor(tex_y / float(_minimap_scale)))

	return _minimap_view_origin + Vector2i(vx, vy)



func _toggle_deploy_tile(cell: Vector2i) -> void:
	RunManager.ensure_floor_config()

	# Only allow toggling inside the generated map rect
	if not _minimap_used_rect.has_point(cell):
		return

	# Only allow walkable tiles
	if not _minimap_is_walkable(preview_terrain, cell):
		return

	# Toggle in deploy_tiles
	var idx: int = RunManager.deploy_tiles.find(cell)
	if idx == -1:
		RunManager.deploy_tiles.append(cell)
	else:
		RunManager.deploy_tiles.remove_at(idx)

	# Rebuild minimap so overlay updates immediately
	_build_static_minimap_from_tilemap(preview_terrain)

func _on_minimap_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
	
		# LEFT = place (requires selected unit)
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var cell := _minimap_local_pos_to_cell(mb.position)
			if cell.x != 999999:
				_try_place_selected_unit_on_cell(cell)

		# RIGHT = drag pan
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_minimap_dragging = true
				_minimap_drag_last_pos = mb.position
				_rmb_down_pos = mb.position
				_rmb_dragged = false
			else:
				_minimap_dragging = false
				# If we released without dragging much, treat it as "unplace"
				if not _rmb_dragged:
					_unplace_selected_deployed_unit()
					_build_static_minimap_from_tilemap(preview_terrain)
					_update_minimap_hint_label()


	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion

		if _minimap_dragging:
			var delta: Vector2 = mm.position - _minimap_drag_last_pos
			# Mark as dragged if we moved more than a tiny threshold
			if (_minimap_drag_last_pos - _rmb_down_pos).length() > 6.0:
				_rmb_dragged = true
			_minimap_drag_last_pos = mm.position

			var dx: int = int(round(delta.x / float(_minimap_scale)))
			var dy: int = int(round(delta.y / float(_minimap_scale)))

			_minimap_view_origin -= Vector2i(dx, dy)
			_build_static_minimap_from_tilemap(preview_terrain)
		else:
			# --- HOVER PREVIEW ---
			var cell := _minimap_local_pos_to_cell(mm.position)
			if cell != _minimap_hover_cell:
				_minimap_hover_cell = cell
				_build_static_minimap_from_tilemap(preview_terrain)
				_update_minimap_hint_label()

func _try_place_selected_unit_on_cell(cell: Vector2i) -> void:
	RunManager.ensure_floor_config()
	_update_minimap_hint_label()


	# Must be inside minimap bounds
	if not _minimap_used_rect.has_point(cell):
		return

	# Must be in deploy zone
	if RunManager.deploy_tiles.find(cell) == -1:
		hint_label.text = "Pick a tile in the deploy zone."
		return

	# Must be walkable
	if not _minimap_is_walkable(preview_terrain, cell):
		hint_label.text = "That tile isn't walkable."
		return

	# Must have a selected deployed unit
	# Must have a selected deployed unit
	var roster_index: int = _get_selected_deployed_roster_index()
	if roster_index < 0:
		hint_label.text = "Select a deployed unit first."
		return

	# If another deployed unit is already on this tile, swap
	var other_roster_index: int = _find_roster_index_placed_on_cell(cell)

	if other_roster_index != -1 and other_roster_index != roster_index and _is_roster_index_deployed(other_roster_index):
		# swap positions between roster_index and other_roster_index
		var my_old: Vector2i = Vector2i(999999, 999999)
		if _placement_by_roster_index.has(roster_index):
			my_old = _placement_by_roster_index[roster_index]

		# Put selected unit onto clicked cell
		_placement_by_roster_index[roster_index] = cell

		# Put the other unit onto selected unit's old cell, if it had one.
		if my_old.x != 999999:
			_placement_by_roster_index[other_roster_index] = my_old
		else:
			# If selected unit wasn't placed yet, just unplace the other one.
			_placement_by_roster_index.erase(other_roster_index)

		hint_label.text = "Swapped units."
		_build_static_minimap_from_tilemap(preview_terrain)
		return

	# Otherwise normal place (empty tile, or occupied by non-deployed/invalid)
	_placement_by_roster_index[roster_index] = cell
	hint_label.text = "Placed unit."
	_build_static_minimap_from_tilemap(preview_terrain)


func _compute_deploy_tiles_from_map(tilemap: TileMap, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if tilemap == null or count <= 0:
		return result

	var used: Rect2i = tilemap.get_used_rect()
	if used.size == Vector2i.ZERO:
		return result

	# band thickness in tiles
	var band_width: int = used.size.x / 6
	if band_width < 3:
		band_width = 3

	var band_height: int = used.size.y / 6
	if band_height < 3:
		band_height = 3

	# 0=left, 1=right, 2=top, 3=bottom (deterministic)
	var side: int = 0
	if "current_map_seed" in RunManager:
		side = abs(int(RunManager.current_map_seed)) % 4

	var candidates: Array[Vector2i] = []

	match side:
		0: # left
			for y in range(used.position.y, used.position.y + used.size.y):
				for x in range(used.position.x, used.position.x + band_width):
					var cell: Vector2i = Vector2i(x, y)
					if _minimap_is_walkable(tilemap, cell):
						candidates.append(cell)

		1: # right
			var x0: int = used.position.x + used.size.x - band_width
			for y in range(used.position.y, used.position.y + used.size.y):
				for x in range(x0, used.position.x + used.size.x):
					var cell: Vector2i = Vector2i(x, y)
					if _minimap_is_walkable(tilemap, cell):
						candidates.append(cell)

		2: # top
			for y in range(used.position.y, used.position.y + band_height):
				for x in range(used.position.x, used.position.x + used.size.x):
					var cell: Vector2i = Vector2i(x, y)
					if _minimap_is_walkable(tilemap, cell):
						candidates.append(cell)

		3: # bottom
			var y0: int = used.position.y + used.size.y - band_height
			for y in range(y0, used.position.y + used.size.y):
				for x in range(used.position.x, used.position.x + used.size.x):
					var cell: Vector2i = Vector2i(x, y)
					if _minimap_is_walkable(tilemap, cell):
						candidates.append(cell)

	if candidates.is_empty():
		return result

	# Deterministic start tile (seeded), not always the middle
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)

	var start_index: int = 0
	if "current_map_seed" in RunManager:
		start_index = abs(int(RunManager.current_map_seed)) % candidates.size()

	var start: Vector2i = candidates[start_index]
	result.append(start)

	while result.size() < count:
		var best_cell: Vector2i = Vector2i.ZERO
		var best_dist: int = 999999
		var found: bool = false

		for c: Vector2i in candidates:
			if result.has(c):
				continue

			var d: int = _min_distance_to_tiles(c, result)
			if d < best_dist:
				best_dist = d
				best_cell = c
				found = true

		if not found:
			break
		result.append(best_cell)

	return result

func _minimap_center_on_deploy() -> void:
	RunManager.ensure_floor_config()
	if RunManager.deploy_tiles.is_empty():
		return

	var sum: Vector2i = Vector2i.ZERO
	for t: Vector2i in RunManager.deploy_tiles:
		sum += t

	var center: Vector2i = sum / RunManager.deploy_tiles.size()
	_minimap_view_origin = center - (_minimap_view_size / 2)

func _draw_minimap_overlays(img: Image, tilemap: TileMap, view_size: Vector2i) -> void:
	var used: Rect2i = _minimap_used_rect
	var deploy_tiles: Array[Vector2i] = _get_preview_deploy_tiles()

	# --- ZONE OVERLAYS ---
	if not deploy_tiles.is_empty():
		var deploy_col := Color(0.05, 0.25, 0.55, 0.65) # darker blue, more alpha
		var enemy_col := Color(0.95, 0.25, 0.25, 0.18)

		var enemy_min_dist: int = 6
		if "enemy_min_spawn_distance" in RunManager:
			enemy_min_dist = int(RunManager.enemy_min_spawn_distance)

		# Deploy tiles
		for t: Vector2i in deploy_tiles:
			var vpos: Vector2i = t - _minimap_view_origin
			if vpos.x < 0 or vpos.y < 0 or vpos.x >= view_size.x or vpos.y >= view_size.y:
				continue
			_minimap_draw_tile_rect(img, vpos.x, vpos.y, _minimap_scale, deploy_col)

		# Enemy zone (only for visible window)
		for vy in range(view_size.y):
			for vx in range(view_size.x):
				var cell: Vector2i = _minimap_view_origin + Vector2i(vx, vy)
				if not used.has_point(cell):
					continue
				if not _minimap_is_walkable(tilemap, cell):
					continue
				if _min_distance_to_tiles(cell, deploy_tiles) >= enemy_min_dist:
					_minimap_draw_tile_rect(img, vx, vy, _minimap_scale, enemy_col)

	# --- UNIT MARKERS ---
# --- UNIT MARKERS ---
	var selected_roster_index: int = _get_selected_deployed_roster_index()

	var marker_col := Color(1, 1, 1, 0.95)
	var outline_col := Color(0, 0, 0, 0.85)

	var selected_marker_col := Color(0.95, 0.90, 0.35, 0.98) # gold-ish
	var selected_ring_col := Color(0.95, 0.90, 0.35, 0.55)   # softer ring

	for k in _placement_by_roster_index.keys():
		var roster_index: int = int(k)
		var cell: Vector2i = _placement_by_roster_index[k]
		var vpos2: Vector2i = cell - _minimap_view_origin
		if vpos2.x < 0 or vpos2.y < 0 or vpos2.x >= view_size.x or vpos2.y >= view_size.y:
			continue

		var cx := vpos2.x * _minimap_scale + _minimap_scale / 2
		var cy := vpos2.y * _minimap_scale + _minimap_scale / 2

		var r_base: int = max(2, _minimap_scale / 5)

	# black outline then marker
		_minimap_draw_dot(img, cx, cy, r_base + 1, outline_col)

		if roster_index == selected_roster_index:
			# extra ring for the selected unit
			_minimap_draw_dot(img, cx, cy, r_base + 4, selected_ring_col)
			_minimap_draw_dot(img, cx, cy, r_base, selected_marker_col)
		else:
			_minimap_draw_dot(img, cx, cy, r_base, marker_col)


	# --- HOVER TILE (FE-style cursor) ---
	if _minimap_hover_cell.x != 999999:
		var vpos := _minimap_hover_cell - _minimap_view_origin
		if vpos.x >= 0 and vpos.y >= 0 and vpos.x < view_size.x and vpos.y < view_size.y:
			var hover_col := Color(1.0, 1.0, 1.0, 0.45) # soft white
			_minimap_draw_tile_outline(img, vpos.x, vpos.y, _minimap_scale, hover_col)

func _minimap_draw_tile_outline(img: Image, x: int, y: int, scale: int, col: Color) -> void:
	var px0 := x * scale
	var py0 := y * scale
	var px1 := px0 + scale - 1
	var py1 := py0 + scale - 1

	for px in range(px0, px1 + 1):
		img.set_pixel(px, py0, col)
		img.set_pixel(px, py1, col)
	for py in range(py0, py1 + 1):
		img.set_pixel(px0, py, col)
		img.set_pixel(px1, py, col)

func _on_MapPreviewTexture_mouse_exited() -> void:
	_minimap_hover_cell = Vector2i(999999, 999999)
	_build_static_minimap_from_tilemap(preview_terrain)

func _find_roster_index_placed_on_cell(cell: Vector2i) -> int:
	for k in _placement_by_roster_index.keys():
		if _placement_by_roster_index[k] == cell:
			return int(k)
	return -1

func _is_roster_index_deployed(roster_index: int) -> bool:
	return _deployed_indices.has(roster_index)

func _update_minimap_hint_label() -> void:
	var roster_index: int = _get_selected_deployed_roster_index()
	if roster_index < 0:
		return # keep whatever hint you already had

	if roster_index >= RunManager.roster.size():
		return

	var data: UnitData = RunManager.roster[roster_index]
	if data == null or data.unit_class == null:
		return

	var unit_name := data.unit_class.display_name
	var lvl := data.level

	var msg := "Placing: %s (Lv %d)" % [unit_name, lvl]

	if _placement_by_roster_index.has(roster_index):
		var placed_cell: Vector2i = _placement_by_roster_index[roster_index]
		msg += " @ (%d,%d)" % [placed_cell.x, placed_cell.y]

	if _minimap_hover_cell.x != 999999:
		msg += " → (%d,%d)" % [_minimap_hover_cell.x, _minimap_hover_cell.y]

	hint_label.text = msg

func _unplace_selected_deployed_unit() -> void:
	var roster_index: int = _get_selected_deployed_roster_index()
	if roster_index < 0:
		hint_label.text = "Select a deployed unit to unplace."
		return

	if _placement_by_roster_index.has(roster_index):
		_placement_by_roster_index.erase(roster_index)
		hint_label.text = "Unplaced unit."
	else:
		hint_label.text = "Unit is not placed."

func _auto_place_deployed_units() -> void:
	RunManager.ensure_floor_config()

	# Remove placements for units no longer deployed
	for k in _placement_by_roster_index.keys():
		var ri: int = int(k)
		if not _deployed_indices.has(ri):
			_placement_by_roster_index.erase(ri)

	# Build occupied set from remaining placements
	var occupied: Dictionary = {} # Vector2i -> true
	for k in _placement_by_roster_index.keys():
		var cell: Vector2i = _placement_by_roster_index[k]
		occupied[cell] = true

	# Keep existing placements if still valid; otherwise clear them
	for ri in _deployed_indices:
		if _placement_by_roster_index.has(ri):
			var keep_cell: Vector2i = _placement_by_roster_index[ri]
			if RunManager.deploy_tiles.has(keep_cell) and _minimap_is_walkable(preview_terrain, keep_cell):
				continue
			_placement_by_roster_index.erase(ri)

	# Place any unplaced deployed units into the first free deploy tiles
	for ri in _deployed_indices:
		if _placement_by_roster_index.has(ri):
			continue

		for cell in RunManager.deploy_tiles:
			if occupied.has(cell):
				continue
			if not _minimap_is_walkable(preview_terrain, cell):
				continue

			_placement_by_roster_index[ri] = cell
			occupied[cell] = true
			break

	hint_label.text = "Auto-placed deployed units."
	_minimap_center_on_deploy()
	_build_static_minimap_from_tilemap(preview_terrain)
	_update_minimap_hint_label()
