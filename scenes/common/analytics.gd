class_name Analytics
extends RefCounted
## The game's one door to the web page's analytics: `window.gcAnalytics`, which
## deploy/web/site/analytics.js defines and which honours the visitor's consent.
##
## A no-op everywhere but a web export — desktop, mobile, headless runs and tests
## never touch the bridge — and on a page whose analytics never loaded.

const JS_INTERFACE := "gcAnalytics"


## Sends one event. Props stay small and anonymous: ids, counts and verdicts,
## never a name a player typed.
static func track(event: String, props: Dictionary = {}) -> void:
	if not OS.has_feature("web"):
		return
	var bridge: Object = JavaScriptBridge.get_interface(JS_INTERFACE)
	if bridge == null:
		return
	# The bridge hands JavaScript no dictionaries, so the props cross as JSON.
	bridge.call("capture", event, JSON.stringify(props))
