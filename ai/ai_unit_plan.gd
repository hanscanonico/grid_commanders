class_name AIUnitPlan
extends RefCounted
## One ready unit's best action this turn, and the facts AIPlanCache judges it by.
##
## Its own file rather than an inner class of the planner, because the cache
## holds them: an inner class would make the two files refer to each other.

var command: Command
var score: float = -INF
## The fill every candidate was drawn from, kept so a plan whose actions still
## hold can have its fallback advance redone without paying for the flood fill
## again — measured, the fill is over half of what scoring a unit costs and the
## advance is a tenth of it.
var reach: MovementResolver.MoveRange
## True when `command` is that fallback advance rather than something the unit
## wanted to do. It is the one half of a plan the ground around the unit cannot
## judge, so the cache tracks it apart.
var advances: bool = false
## Whether the advance is the goal cohesion shapes — the advance on the enemy —
## so the cache knows a marching column can move it.
var keeps_formation: bool = false
