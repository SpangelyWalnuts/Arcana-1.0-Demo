extends Control

@onready var floor_label: Label          = $Panel/VBoxContainer/FloorLabel
@onready var hint_label: Label           = $Panel/VBoxContainer/HintLabel
@onready var roster_list: ItemList       = $Panel/VBoxContainer/HBoxContainer/RosterBox/RosterList
@onready var deploy_list: ItemList       = $Panel/VBoxContainer/HBoxContainer/DeployBox/DeployList
@onready var start_button: Button        = $Panel/VBoxContainer/HBoxContainer/HBoxContainer/StartBattleButton
@onready var title_button: Button        = $Panel/VBoxContainer/HBoxContainer/HBoxContainer/ReturnToTitleButton
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

#SHOP
@onready var shop_button: Button = $Panel/VBoxContainer/HBoxContainer/HBoxContainer/ShopButton

@onready var shop_dialog: AcceptDialog     = $ShopDialog
@onready var shop_list: ItemList           = $ShopDialog/VBoxContainer/ShopList
@onready var shop_gold_label: Label        = $ShopDialog/VBoxContainer/GoldLabel
@onready var shop_details_label: Label     = $ShopDialog/VBoxContainer/DetailsLabel
@onready var shop_buy_button: Button       = $ShopDialog/VBoxContainer/HBoxContainer/BuyButton
@onready var shop_close_button: Button     = $ShopDialog/VBoxContainer/HBoxContainer/CloseButton

@onready var unit_name_label: Label = $Panel/VBoxContainer/HBoxContainer/DetailsBox/UnitNameLabel

# Track which unit is currently selected in the roster
var _selected_roster_index: int = -1
# Temporary: limit on how many units can be deployed this floor.
# Later we’ll hook this to map size / enemy count via some floor config.
@export var max_deploy_slots: int = 4

# Indices into RunManager.roster that are currently deployed
var _deployed_indices: Array[int] = []


func _ready() -> void:
	if not RunManager.run_active:
		RunManager.return_to_title()
		return

	floor_label.text = "Floor %d" % RunManager.current_floor
	hint_label.text = "Select up to %d units to deploy." % max_deploy_slots

	_populate_roster_lists()

	# Double-click to move units between lists
	roster_list.item_activated.connect(_on_roster_item_activated)
	deploy_list.item_activated.connect(_on_deploy_item_activated)

	# Single-click to show details
	roster_list.item_selected.connect(_on_roster_item_selected)


	start_button.pressed.connect(_on_start_battle_pressed)
	title_button.pressed.connect(_on_return_to_title_pressed)

	manage_arcana_button.pressed.connect(_on_manage_arcana_pressed)
	arcana_popup.confirmed.connect(_on_arcana_popup_confirmed)
	
	manage_equipment_button.pressed.connect(_on_manage_equipment_pressed)
	manage_items_button.pressed.connect(_on_manage_items_pressed)

	equipment_popup.confirmed.connect(_on_equipment_popup_confirmed)
	items_popup.confirmed.connect(_on_items_popup_confirmed)

	shop_button.pressed.connect(_on_shop_button_pressed)

	shop_list.item_selected.connect(_on_shop_item_selected)
	shop_buy_button.pressed.connect(_on_shop_buy_pressed)
	shop_close_button.pressed.connect(func() -> void:
		shop_dialog.hide()
	)


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
	if data.equipment_slots.size() == 0:
		equipment_label.text = "Equipment: (none)"
	else:
		var eq_names: Array[String] = []
		for eq in data.equipment_slots:
			if eq != null:
				eq_names.append(eq.name)
		equipment_label.text = "Equipment: " + ", ".join(eq_names)

	# --- Item slots ---
	if data.item_slots.size() == 0:
		items_label.text = "Items: (none)"
	else:
		var item_names: Array[String] = []
		for it in data.item_slots:
			if it != null:
				item_names.append(it.name)
		items_label.text = "Items: " + ", ".join(item_names)


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
		roster_list.add_item(label_text)



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

		roster_list.add_item(text)

	# --- Rebuild deployed list in the same order as _deployed_indices ---
	for roster_index in _deployed_indices:
		if roster_index < 0 or roster_index >= roster.size():
			continue

		var data: UnitData = roster[roster_index]
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		deploy_list.add_item("%s (Lv %d)" % [cls.display_name, data.level])


func _on_start_battle_pressed() -> void:
	if _deployed_indices.is_empty():
		return  # Maybe later show a warning: "Select at least one unit."

	var roster = RunManager.roster
	RunManager.deployed_units.clear()

	for idx in _deployed_indices:
		if idx < 0 or idx >= roster.size():
			continue

		var data: UnitData = roster[idx]
		if data != null:
			RunManager.deployed_units.append(data)

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

#SHOP UI Logic
func _on_shop_button_pressed() -> void:
	_refresh_shop_ui()
	shop_dialog.popup_centered()


func _refresh_shop_ui() -> void:
	shop_list.clear()

	var stock: Array = RunManager.shop_stock

	for i in range(stock.size()):
		var entry = stock[i]
		var res = entry.get("resource", null)
		var type_str: String = String(entry.get("type", ""))
		var price: int = int(entry.get("price", 0))
		var remaining: int = int(entry.get("stock", 0))

		var name: String = "Unknown"
		if res is Equipment or res is Item:
			name = res.name

		var text := "%s - %dG (x%d)" % [name, price, remaining]
		shop_list.add_item(text)

	shop_gold_label.text = "Gold: %d" % RunManager.gold
	shop_details_label.text = "Select an item to see details."


func _on_shop_item_selected(index: int) -> void:
	var stock: Array = RunManager.shop_stock
	if index < 0 or index >= stock.size():
		return

	var entry = stock[index]
	var res = entry.get("resource", null)
	var desc: String = ""

	if res is Equipment or res is Item:
		desc = res.description

	var price: int = int(entry.get("price", 0))
	var remaining: int = int(entry.get("stock", 0))

	shop_details_label.text = "%s\n\nPrice: %dG\nStock: %d" % [desc, price, remaining]
#Buy Handler
func _on_shop_buy_pressed() -> void:
	var selected_indices := shop_list.get_selected_items()
	if selected_indices.is_empty():
		shop_details_label.text = "No item selected."
		return

	var idx: int = selected_indices[0]

	var result: Dictionary = RunManager.try_buy_from_shop(idx)
	if not bool(result.get("success", false)):
		var reason: String = String(result.get("reason", "Cannot buy."))
		shop_details_label.text = reason
		return

	# Purchase successful
	shop_details_label.text = "Purchased!"
	_refresh_shop_ui()

	# Optional: you could also refresh the details panel of the selected unit
	# if you want to auto-show new equipment options, etc.
