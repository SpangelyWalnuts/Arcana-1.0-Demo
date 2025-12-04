extends Resource
class_name BattleObjective

# Types of victory conditions we'll support.
# For now, we'll implement ROUT (defeat all enemies),
# and leave the others ready to be used later.
enum VictoryType {
	ROUT,          # Defeat all enemies
	DEFEAT_BOSS,   # Defeat specific boss unit(s)
	DEFEAT_AMOUNT, # Defeat a number of enemies
	ESCAPE,        # Get all player units to escape tiles
	DEFEND,        # Survive for N turns
	ACTIVATE       # Activate N objectives on the map
}

@export var victory_type: VictoryType = VictoryType.ROUT

# --- Parameters for future conditions (ignored for ROUT for now) ---

# For DEFEAT_BOSS: enemies in this group count as bosses.
# Example: put boss enemy units in group "boss".
@export var boss_group: StringName = &"boss"

# For DEFEAT_AMOUNT: number of enemies to defeat.
@export var required_kills: int = 0

# For ESCAPE: how many player units must escape.
@export var required_escapes: int = 0

# For DEFEND: how many turns to survive.
@export var defend_turns: int = 0

# For ACTIVATE: how many objectives must be activated.
@export var required_activations: int = 0
