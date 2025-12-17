extends Resource
class_name BiomeChunkDB

@export var entries: Array[ChunkAdjacencyEntry] = []

func get_entry(scene: PackedScene) -> ChunkAdjacencyEntry:
	if scene == null:
		return null
	for e in entries:
		if e != null and e.chunk == scene:
			return e
	return null

func get_all_chunks() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for e in entries:
		if e != null and e.chunk != null:
			out.append(e.chunk)
	return out
