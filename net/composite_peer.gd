class_name CompositePeer
extends MultiplayerPeerExtension
## The server's peer when it serves several transports at once (PLAN §3.20
## rule 2): one MultiplayerPeer for SceneMultiplayer over one adapter per
## transport (ENet for native clients, WebSocket for browsers).
##
## - IDs: the server is 1. Each adapter assigns its clients' ids and tells
##   them (ENet and WebSocket both do), so a client's get_unique_id() matches;
##   an id already used by another transport is rejected (the client retries).
## - Admission stays with SceneMultiplayer's auth (Transport's handshake):
##   this peer reports a connection as soon as its transport does, and
##   SceneMultiplayer keeps it pre-admission until the HELLO is accepted.
## - Every packet keeps its sender, channel and transfer mode. WebSocket has
##   one reliable ordered stream: its packets arrive as reliable channel 0
##   (the protocol dispatches by message type, so no channel tag is needed;
##   there's no channel isolation over WebSocket).
## - Routing: a target id goes to its transport; 0 broadcasts on every
##   transport; -id broadcasts everywhere except that peer.
## - Exactly one peer_connected / peer_disconnected per client.

var adapters: Array[MultiplayerPeer] = []

var _owner: Dictionary = {}  ## peer id -> adapter
var _queue: Array = []  ## [peer id, channel, mode, data], oldest first
var _target: int = 0
var _channel: int = 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refusing: bool = false
var _closed: bool = false


## `peers`: server-mode peers that are already listening.
func _init(peers: Array[MultiplayerPeer] = []) -> void:
	for p in peers:
		add_adapter(p)


func add_adapter(peer: MultiplayerPeer) -> void:
	adapters.append(peer)
	peer.peer_connected.connect(_on_adapter_connected.bind(peer))
	peer.peer_disconnected.connect(_on_adapter_disconnected.bind(peer))


## The adapter serving peer `id` (null if unknown).
func adapter_of(id: int) -> MultiplayerPeer:
	return _owner.get(id)


func _on_adapter_connected(id: int, adapter: MultiplayerPeer) -> void:
	if id <= 1 or _owner.has(id):
		adapter.disconnect_peer(id, true)  # id collision across transports
		return
	_owner[id] = adapter
	peer_connected.emit(id)


func _on_adapter_disconnected(id: int, adapter: MultiplayerPeer) -> void:
	if _owner.get(id) == adapter:
		_owner.erase(id)
		peer_disconnected.emit(id)


func _poll() -> void:
	for adapter in adapters:
		adapter.poll()
		while adapter.get_available_packet_count() > 0:
			var from := adapter.get_packet_peer()
			var channel := adapter.get_packet_channel()
			var mode := adapter.get_packet_mode()
			var data := adapter.get_packet()
			if _owner.get(from) == adapter:
				_queue.append([from, channel, mode, data])


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_script() -> PackedByteArray:
	return _queue.pop_front()[3] if not _queue.is_empty() else PackedByteArray()


func _get_packet_peer() -> int:
	return _queue[0][0] if not _queue.is_empty() else 0


func _get_packet_channel() -> int:
	return _queue[0][1] if not _queue.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _queue[0][2] if not _queue.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _target > 0:
		var adapter: MultiplayerPeer = _owner.get(_target)
		return _send(adapter, _target, buffer) if adapter != null else ERR_UNAVAILABLE
	var err := OK
	for adapter in adapters:
		# Exclusion: only the excluded peer's own transport needs it.
		var target := _target if _target < 0 and _owner.get(-_target) == adapter else 0
		var e := _send(adapter, target, buffer)
		err = e if e != OK else err
	return err


func _send(adapter: MultiplayerPeer, target: int, buffer: PackedByteArray) -> Error:
	adapter.set_target_peer(target)
	adapter.transfer_mode = _mode
	# One reliable ordered stream: WebSocket has no other channels.
	adapter.transfer_channel = 0 if adapter is WebSocketMultiplayerPeer else _channel
	return adapter.put_packet(buffer)


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _get_max_packet_size() -> int:
	var size := 1 << 24
	for adapter in adapters:
		size = mini(size, adapter.get_max_packet_size())
	return size


func _get_unique_id() -> int:
	return 1


func _is_server() -> bool:
	return true


func _is_server_relay_supported() -> bool:
	return false


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable
	for adapter in adapters:
		adapter.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return MultiplayerPeer.CONNECTION_DISCONNECTED if _closed else MultiplayerPeer.CONNECTION_CONNECTED


func _disconnect_peer(peer: int, force: bool) -> void:
	var adapter: MultiplayerPeer = _owner.get(peer)
	if adapter == null:
		return
	adapter.disconnect_peer(peer, force)
	if force and _owner.has(peer):
		# A forced drop may not be reported by the transport.
		_owner.erase(peer)
		peer_disconnected.emit(peer)


func _close() -> void:
	for adapter in adapters:
		adapter.close()
	_owner.clear()
	_queue.clear()
	_closed = true
