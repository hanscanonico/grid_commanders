// PostHog analytics for gridcommanders.com, shared by the landing page and the
// game under /play/, so the key and the consent banner live once. See README's
// "Web build" for what is tracked.
//
// Until a visitor chooses, PostHog keeps its state in memory: no cookie and no
// localStorage, so a page view counts but a returning visitor is not recognised.
// Accept switches to cookie persistence; Decline stops capturing. The choice is
// remembered in localStorage under CHOICE_KEY, and a declined visitor's next
// pages never load PostHog at all.
(function () {
	"use strict";

	// The PostHog project API key (public by design). Set it back to the
	// placeholder phc_REPLACE_ME to switch analytics off.
	var KEY = "phc_x4Nrd4nfUyBF7sTTYZFEz9obMaL5Zd6KdxahokNZZMss";
	var API_HOST = "https://eu.i.posthog.com";
	var UI_HOST = "https://eu.posthog.com";
	var CHOICE_KEY = "gc-analytics-consent";

	var live = false;

	// The one entry point the game calls (Analytics.track in Godot). Props arrive
	// as a JSON string because the engine's bridge passes no dictionaries.
	window.gcAnalytics = {
		capture: function (event, props) {
			if (!live || !window.posthog) return;
			try {
				window.posthog.capture(String(event), typeof props === "string" ? JSON.parse(props) : props || {});
			} catch (e) {}
		}
	};

	if (KEY === "phc_REPLACE_ME" || /^\/admin/.test(location.pathname)) return;

	var choice = null;
	try {
		choice = localStorage.getItem(CHOICE_KEY);
	} catch (e) {}
	if (choice === "denied") return;

	// PostHog's official loader snippet: queues calls until array.js arrives from
	// eu-assets.i.posthog.com.
	/* eslint-disable */
	!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
	/* eslint-enable */

	window.posthog.init(KEY, {
		api_host: API_HOST,
		ui_host: UI_HOST,
		persistence: choice === "granted" ? "localStorage+cookie" : "memory",
		person_profiles: "identified_only",
		capture_pageview: true,
		capture_pageleave: true,
		autocapture: false,
		disable_session_recording: true
	});
	live = true;

	if (choice !== "granted") showBanner();

	function remember(value) {
		try {
			localStorage.setItem(CHOICE_KEY, value);
		} catch (e) {}
	}

	function accept() {
		remember("granted");
		window.posthog.set_config({ persistence: "localStorage+cookie" });
		window.posthog.opt_in_capturing();
	}

	function decline() {
		remember("denied");
		live = false;
		window.posthog.opt_out_capturing();
	}

	// A thin bar along the bottom edge. It never takes focus, so the game keeps
	// the keyboard, and it is gone for good after either button.
	function showBanner() {
		var bar = document.createElement("div");
		bar.setAttribute("role", "region");
		bar.setAttribute("aria-label", "Analytics consent");
		bar.style.cssText = [
			"position:fixed", "left:0", "right:0", "bottom:0", "z-index:2147483647",
			"display:flex", "flex-wrap:wrap", "align-items:center", "justify-content:center",
			"gap:6px 12px", "padding:6px 12px", "background:rgba(35,39,43,0.96)",
			"border-top:1px solid #3a3f45", "color:#eee7d6",
			"font:13px/1.4 ui-sans-serif,system-ui,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"
		].join(";");
		var text = document.createElement("span");
		text.textContent = "We count visits with PostHog to learn whether people play. Allow a cookie to tell return visits apart?";
		bar.appendChild(text);
		bar.appendChild(button("Accept", "#6cc24a", "#111618", accept));
		bar.appendChild(button("Decline", "transparent", "#eee7d6", decline));

		function button(label, background, color, choose) {
			var b = document.createElement("button");
			b.type = "button";
			b.textContent = label;
			b.style.cssText = [
				"padding:4px 14px", "font:inherit", "font-weight:700", "cursor:pointer",
				"border:1px solid #8a9099", "border-radius:3px",
				"background:" + background, "color:" + color
			].join(";");
			b.addEventListener("click", function (event) {
				event.stopPropagation();
				choose();
				bar.remove();
			});
			return b;
		}

		var attach = function () {
			document.body.appendChild(bar);
		};
		if (document.body) attach();
		else document.addEventListener("DOMContentLoaded", attach);
	}
})();
