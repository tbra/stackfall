class_name NetSteamSession
extends RefCounted
## The Steam lobby session of the Net autoload: lobby generation and the FIFO of
## pending requests, the lobby list, invites. Stub: the bodies are replaced when
## the logic moves out of autoload/Net.gd; nothing calls it yet.

var _steam: SteamClient
var _transport: NetTransport
var _roster: NetRoster


func _init(steam: SteamClient, transport: NetTransport, roster: NetRoster) -> void:
	_steam = steam
	_transport = transport
	_roster = roster


func host_online(_player_name: String = "") -> Error:
	push_error("NetSteamSession.host_online: not implemented")
	return ERR_UNAVAILABLE


func join_lobby(_lobby_id: int, _player_name: String = "") -> Error:
	push_error("NetSteamSession.join_lobby: not implemented")
	return ERR_UNAVAILABLE


func refresh_lobby_list() -> void:
	push_error("NetSteamSession.refresh_lobby_list: not implemented")


func leave() -> void:
	push_error("NetSteamSession.leave: not implemented")
