extends Resource
class_name ChunkAdjacencyEntry

@export var chunk: PackedScene

# Allowed neighbors for this chunk (explicit, per direction)
@export var allow_north: Array[PackedScene] = []
@export var allow_east:  Array[PackedScene] = []
@export var allow_south: Array[PackedScene] = []
@export var allow_west:  Array[PackedScene] = []

@export var weight: float = 1.0

@export var any_north: bool = false
@export var any_east: bool = false
@export var any_south: bool = false
@export var any_west: bool = false
