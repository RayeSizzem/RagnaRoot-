extends Node
## The settlement economy. Lives as a node in main.tscn (group "resource_bank").

signal changed(kind: String, amount: int)

## Starting stash (tripled): enough to open with towers and a hut or two.
@export var start_timber: int = 180
@export var start_stone: int = 90

var _bank := {
	"sap": 0,
	"authority": 0,
	"timber": 0,
	"stone": 0,
	"forage": 0,
	"glow": 0,
	"folk": 0,
	"essence": 0,
	"soft_wood": 0,
	"hard_wood": 0,
	"gold": 0,
	"ruby": 0,
	"diamond": 0,
	"grain": 0,
	"meat": 0,
	"holy_light": 0,
}


func _enter_tree() -> void:
	add_to_group("resource_bank")


func _ready() -> void:
	_bank["timber"] = start_timber
	_bank["stone"] = start_stone
	changed.emit("timber", _bank["timber"])
	changed.emit("stone", _bank["stone"])


func get_amount(kind: String) -> int:
	return _bank.get(kind, 0)


func add(kind: String, amount: int) -> void:
	if not _bank.has(kind):
		_bank[kind] = 0
	_bank[kind] += amount
	changed.emit(kind, _bank[kind])


func spend(kind: String, amount: int) -> bool:
	if _bank.get(kind, 0) < amount:
		return false
	_bank[kind] -= amount
	changed.emit(kind, _bank[kind])
	return true


## costs = { "timber": n, "stone": n, ... }
func can_afford(costs: Dictionary) -> bool:
	for k in costs.keys():
		if _bank.get(k, 0) < int(costs[k]):
			return false
	return true


func spend_many(costs: Dictionary) -> bool:
	if not can_afford(costs):
		return false
	for k in costs.keys():
		_bank[k] -= int(costs[k])
		changed.emit(k, _bank[k])
	return true


func snapshot() -> Dictionary:
	return _bank.duplicate()
