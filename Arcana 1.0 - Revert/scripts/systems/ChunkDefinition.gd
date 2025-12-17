extends Node
class_name ChunkDefinition

@export var allow_north: Array[PackedScene] = []
@export var allow_east:  Array[PackedScene] = []
@export var allow_south: Array[PackedScene] = []
@export var allow_west:  Array[PackedScene] = []

@export var weight: float = 1.0
@export var tags: Array[StringName] = []
