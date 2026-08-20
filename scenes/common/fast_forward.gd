class_name FastForward
extends RefCounted
## The held key that hurries the theatre along, without changing the speed tier.
##
## A tier is a preference: it says how a match should be paced from here on.
## This is a momentary answer to one slow moment — the same thing Re-Boot Camp's
## held trigger is — so it is read where time is spent rather than stored
## anywhere, and releasing the key is nothing more than the next read coming back
## at 1.0.
##
## Presentation only, and deliberately not a `GameSpeed` tier: `GameSpeed` is a
## frozen table of numbers, this is a live read of the keyboard, and a tier that
## a player could not pick from the menu would be a second, invisible answer to
## "what speed is this match at". Nothing under `core/` or `ai/` may reach either
## of them.
##
## Only time already scaled by a tier passes through here, so Instant needs no
## branch: its beats are zero seconds long and stay zero however hard the key is
## held.

## How much faster the held key plays a beat. Fast enough to be worth reaching
## for, and short of the rate at which a cut-in stops reading as an exchange.
const SCALE := 3.5


## True while the player is holding the key down. Polled rather than driven by an
## event, because what is wanted is the state of the key *now*, at the moment a
## frame of a cut-in or a beat between two AI commands is about to be spent.
static func held() -> bool:
	return Input.is_action_pressed(&"fast_forward")


## The multiplier on elapsed time this frame: `SCALE` while the key is down and
## 1.0 otherwise. Callers that wait for a duration divide by it; callers that
## advance a clock multiply.
static func rate() -> float:
	return SCALE if held() else 1.0
