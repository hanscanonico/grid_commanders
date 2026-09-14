// The shell: it lists whatever panels the server registered and renders the
// selected one. A new panel is a new module on the server plus a render_<slug>
// function here — nothing else on this page changes.
"use strict";

const RANGES = ["7d", "30d", "90d", "365d"];
const state = { panel: null, range: "7d", panels: [] };

const el = (tag, attrs = {}, kids = []) => {
	const node = document.createElement(tag);
	for (const [key, value] of Object.entries(attrs)) {
		if (key === "text") node.textContent = value;
		else node.setAttribute(key, value);
	}
	for (const kid of kids) node.appendChild(kid);
	return node;
};

const svgEl = (tag, attrs = {}) => {
	const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
	for (const [key, value] of Object.entries(attrs)) {
		if (key === "text") node.textContent = value;
		else node.setAttribute(key, value);
	}
	return node;
};

const number = (value) => value.toLocaleString();

function card(title, kids) {
	return el("section", { class: "card" }, [el("h2", { text: title }), ...kids]);
}

function table(heading, rows) {
	const head = el("thead", {}, [
		el("tr", {}, [
			el("th", { text: heading }),
			el("th", { class: "n", text: "Views" }),
			el("th", { class: "n", text: "Uniques" }),
		]),
	]);
	const body = el("tbody");
	if (rows.length === 0) {
		body.appendChild(el("tr", {}, [el("td", { colspan: "3", text: "—" })]));
	}
	for (const row of rows) {
		body.appendChild(
			el("tr", {}, [
				el("td", { text: row.key === "" ? "(none)" : row.key }),
				el("td", { class: "n", text: number(row.views) }),
				el("td", { class: "n", text: number(row.uniques) }),
			]),
		);
	}
	return el("table", {}, [head, body]);
}

// One bar per day, drawn against the busiest day in the range.
function chart(daily) {
	const width = 1000;
	const height = 180;
	const floor = height - 18;
	const peak = Math.max(1, ...daily.map((day) => day.views));
	const step = width / Math.max(1, daily.length);
	const svg = svgEl("svg", {
		viewBox: `0 0 ${width} ${height}`,
		preserveAspectRatio: "none",
		role: "img",
		"aria-label": "Pageviews per day",
	});
	daily.forEach((day, index) => {
		const tall = Math.round((day.views / peak) * floor);
		const bar = svgEl("rect", {
			x: (index * step + step * 0.15).toFixed(1),
			y: floor - tall,
			width: (step * 0.7).toFixed(1),
			height: Math.max(tall, day.views > 0 ? 1 : 0),
		});
		bar.appendChild(svgEl("title", { text: `${day.day}: ${day.views} views` }));
		svg.appendChild(bar);
	});
	const label = (index, anchor) =>
		svgEl("text", {
			class: "axis",
			x: Math.min(width - 2, Math.max(2, index * step + step / 2)),
			y: height - 4,
			"text-anchor": anchor,
			text: daily[index].day,
		});
	if (daily.length > 0) {
		svg.appendChild(label(0, "start"));
		svg.appendChild(label(daily.length - 1, "end"));
	}
	return svg;
}

function render_traffic(data) {
	const headline = el("div", { class: "headline" }, [
		el("div", {}, [
			el("b", { text: number(data.views) }),
			el("span", { text: "pageviews" }),
		]),
		el("div", {}, [
			el("b", { text: number(data.uniques) }),
			el("span", { text: "unique visitors" }),
		]),
		el("div", {}, [
			el("b", { text: data.range }),
			el("span", { text: `${data.from} → ${data.to}` }),
		]),
	]);
	const tables = el("div", { class: "tables" }, [
		card("Landing page", [table("Path", data.breakdowns.path)]),
		card("Country", [table("Country", data.breakdowns.country)]),
		card("Referrer", [table("Host", data.breakdowns.referrer_host)]),
		card("Device", [table("Class", data.breakdowns.device)]),
		card("Campaign source", [table("utm_source", data.breakdowns.utm_source)]),
		card("Campaign medium", [table("utm_medium", data.breakdowns.utm_medium)]),
		card("Campaign", [table("utm_campaign", data.breakdowns.utm_campaign)]),
	]);
	return [
		headline,
		card("Pageviews per day", [chart(data.daily)]),
		tables,
		el("p", {
			class: "note",
			text:
				"Cookieless and IP-free: a visitor is a hash salted with the day, so" +
				" the same person counts once per day and cannot be followed across" +
				" days. A range's uniques is therefore the sum of daily uniques, not" +
				" distinct people over the range. Bots are dropped by user agent.",
		}),
	];
}

const RENDERERS = { traffic: render_traffic };

async function load() {
	const body = document.getElementById("body");
	body.replaceChildren(el("p", { class: "note", text: "Loading…" }));
	try {
		const response = await fetch(
			`/admin/api/${state.panel}?range=${state.range}`,
			{ credentials: "same-origin" },
		);
		if (!response.ok) throw new Error(`HTTP ${response.status}`);
		const data = await response.json();
		const render = RENDERERS[state.panel];
		body.replaceChildren(
			...(render
				? render(data)
				: [el("p", { class: "note", text: "This panel has no renderer yet." })]),
		);
	} catch (error) {
		body.replaceChildren(
			el("p", { class: "note", text: `Could not load the panel: ${error.message}` }),
		);
	}
}

function drawBar() {
	const panelNav = document.getElementById("panels");
	panelNav.replaceChildren(
		...state.panels.map((panel) => {
			const button = el("button", {
				type: "button",
				text: panel.name,
				"aria-current": String(panel.slug === state.panel),
			});
			button.addEventListener("click", () => {
				state.panel = panel.slug;
				drawBar();
				load();
			});
			return button;
		}),
	);
	const rangeNav = document.getElementById("ranges");
	rangeNav.replaceChildren(
		...RANGES.map((range) => {
			const button = el("button", {
				type: "button",
				text: range,
				"aria-current": String(range === state.range),
			});
			button.addEventListener("click", () => {
				state.range = range;
				drawBar();
				load();
			});
			return button;
		}),
	);
}

async function start() {
	const response = await fetch("/admin/api/panels", {
		credentials: "same-origin",
	});
	state.panels = await response.json();
	state.panel = state.panels.length > 0 ? state.panels[0].slug : null;
	drawBar();
	if (state.panel) load();
}

start();
