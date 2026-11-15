extends RefCounted

enum Action { NONE, PASS, SHOOT, TRAP, TACKLE }

var tick := 0
var player_id := 0
var move := Vector2.ZERO
var look_yaw := 0.0
var look_pitch := 0.0
var sprint := false
var align := false
var action := Action.NONE
var power := 0.0
var lofted := false
var target_id := -1
