class_name MatchPreload
extends RefCounted
## Loads a match's meshes one file at a time while the worker pool is idle,
## behind the loading cover, before the match scene is built.
##
## Godot 4.7.2's Mobile renderer can deadlock (godotengine/godot#123060,
## fixed for 4.8 by #123312): a load that compiles a new shader holds the
## renderer's shader lock while it waits for the compile on the worker pool,
## and pipeline compiles already queued there take every worker and wait for
## that lock. With a cold shader cache the menu's backdrop still has pipelines
## compiling when a quick join loads the map, and the client froze for good
## (4 of 4 cold joins on an AMD laptop). Waiting for the pool to go idle
## before each file leaves it free to run the compile, and the match then
## finds every file in the resource cache.

## A posted no-op that runs within this long finds the pool idle.
const IDLE_US := 3000

## The files, kept loaded until the match has built its scene.
static var _held: Array[Resource] = []


## Every file a match on `map_id` loads meshes or materials from, the map's
## own pieces before the map scene.
static func paths(map_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if Maps.has(map_id):
		var info: Dictionary = Maps.LIST[map_id]
		for scene: String in [info.gameplay, info.presentation]:
			for dep in _dependencies(scene):
				if dep.get_extension() in ["res", "tres", "glb", "gltf", "fbx", "tscn", "scn", "mesh"] and not out.has(dep):
					out.append(dep)
			out.append(scene)
	out.append_array(WeaponModels.paths())
	# Only the selectable characters: their clips are baked (MeshyRig
	# anims_path), so the older rigs and the animation library they were
	# retargeted from never load in a match.
	out.append_array(MeshyRig.paths())
	return out


## Loads `paths`, waiting for an idle pool before each; `progress` gets 0..1.
static func run(tree: SceneTree, files: PackedStringArray, progress: Callable = Callable()) -> void:
	for i in files.size():
		if not ResourceLoader.exists(files[i]):
			continue
		await wait_for_idle_pool(tree)
		_held.append(load(files[i]))
		if progress.is_valid():
			progress.call(float(i + 1) / files.size())


## Lets the match's own loads go back to the cache's normal lifetime.
static func release() -> void:
	_held.clear()


## Returns once a task posted to the worker pool runs within a few
## milliseconds: no queue ahead of it and a thread free. Frames keep running
## while the pool is busy.
static func wait_for_idle_pool(tree: SceneTree) -> void:
	while true:
		var task := WorkerThreadPool.add_task(func() -> void: pass, true)
		var posted := Time.get_ticks_usec()
		while not WorkerThreadPool.is_task_completed(task) and Time.get_ticks_usec() - posted < IDLE_US:
			OS.delay_usec(100)
		var idle := WorkerThreadPool.is_task_completed(task)
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		if idle:
			return
		await tree.process_frame


static func _dependencies(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for dep in ResourceLoader.get_dependencies(path):
		# "uid://…::Type::res://path" (or just the path in older formats).
		var file := dep.get_slice("::", dep.get_slice_count("::") - 1)
		if file.begins_with("uid://"):
			file = ResourceUID.uid_to_path(file)
		if file.begins_with("res://"):
			out.append(file)
	return out
