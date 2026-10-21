extends Node3D
## Frigate reactor core. Only hittable once the shield is down.

var game
var frigate
var hp := 40.0
var max_hp := 40.0
var radius := 8.0
var kind := "REACTOR CORE"
var alive := true


func targetable() -> bool:
	return alive and not frigate.shield_up and not frigate.dying


func velocity() -> Vector3:
	return Vector3.ZERO


func hit(dmg: float, pos: Vector3) -> void:
	if not targetable():
		return
	hp -= dmg
	game.fx.sparks(pos, Color(1.0, 0.6, 0.3))
	frigate.core_flash = 1.0
	if hp <= 0.0:
		alive = false
		game.on_kill(self)
		frigate.on_core_destroyed()
