class_name ScreenshotUtil
extends RefCounted
## Shared --screenshot support for scenes: wait for the first frames to
## render, save the viewport, and quit. Used for automated visual checks.

const SCREENSHOT_ARG := "--screenshot"
## How long the tree is given to settle before the viewport is read. A capture's
## own checks run on this same frame (see `gate`), so what is measured and what
## is photographed are one layout rather than two.
const SETTLE_FRAMES := 8


## The path `--screenshot=` asked for, or "" on an ordinary run. A scene that
## photographs itself asks this instead of rescanning the command line — and it
## is also how it knows to pin whatever a capture must not vary on, such as the
## device's speed preference.
static func requested() -> String:
	return CmdArgs.value(CmdArgs.user(), SCREENSHOT_ARG)


## Waits out the settle, asks the gate, writes the frame. Returns the gate's
## verdict — a false saves nothing. Callers own what happens next: a quit for
## a single capture (capture_and_quit), a scene reload for a smoke batch
## (BattleScenarioDriver, COM-117) — so the shutter discipline byte-stable
## captures depend on has exactly one spelling.
static func save_frame(node: Node, path: String, gate: Callable = Callable()) -> bool:
	for i in SETTLE_FRAMES:
		await node.get_tree().process_frame
	if gate.is_valid():
		var passed: bool = gate.call()
		if not passed:
			return false
	# macOS stops presenting a fully occluded window, and the viewport texture
	# then holds the last frame that actually reached the screen — a capture
	# window buried under the developer's own windows photographed one stale
	# frame under every later scenario's name (COM-117), and a window occluded
	# from birth photographs a blank. The forced draw makes the image below
	# this frame, whatever the window server thinks of the window.
	RenderingServer.force_draw()
	var image := node.get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("screenshot: saved to %s (err=%d)" % [path, err])
	return true


## Saves the viewport and quits zero. `gate` is an optional `func() -> bool` a
## caller passes to make a claim about the frame: it is called on the settled
## frame, immediately before the image is written, and a false verdict quits
## non-zero with nothing saved — which is the whole signal `make smoke` reads,
## since a capture written anyway quits zero.
static func capture_and_quit(node: Node, path: String, gate: Callable = Callable()) -> void:
	if await save_frame(node, path, gate):
		node.get_tree().quit()
	else:
		node.get_tree().quit(1)
