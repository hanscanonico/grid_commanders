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

// Seconds as a reader says them: a bounce in seconds, a session in minutes,
// and a card's total — which is everyone's time added up — in hours rather
// than in four digits of minutes.
const duration = (seconds) => {
	if (seconds < 60) return `${seconds} s`;
	if (seconds < 3600) return `${Math.round(seconds / 60)} min`;
	return `${Math.round(seconds / 3600)} h`;
};

const VIEW_COLUMNS = [
	["Views", (row) => number(row.views)],
	["Uniques", (row) => number(row.uniques)],
];
const TIME_COLUMNS = [
	["Visitors", (row) => number(row.visitors)],
	["Time", (row) => duration(row.seconds)],
];

function card(title, kids) {
	return el("section", { class: "card" }, [el("h2", { text: title }), ...kids]);
}

function table(heading, rows, columns = VIEW_COLUMNS) {
	const head = el("thead", {}, [
		el("tr", {}, [
			el("th", { text: heading }),
			...columns.map(([label]) => el("th", { class: "n", text: label })),
		]),
	]);
	const body = el("tbody");
	if (rows.length === 0) {
		body.appendChild(
			el("tr", {}, [
				el("td", { colspan: String(columns.length + 1), text: "—" }),
			]),
		);
	}
	for (const row of rows) {
		body.appendChild(
			el("tr", {}, [
				el("td", { text: row.key === "" ? "(none)" : row.key }),
				...columns.map(([, cell]) => el("td", { class: "n", text: cell(row) })),
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

const percent = (part, whole) =>
	whole === 0 ? "0%" : `${Math.round((part / whole) * 100)}%`;

// The two numbers that tell a person from a scanner: how many visitors the
// heartbeat could measure at all, and how many of the people who saw the pitch
// went on to open the game.
const engaged_share = (data) => percent(data.engaged_visitors, data.uniques);
const played_share = (data) => percent(data.played_uniques, data.landing_uniques);

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
			el("b", { text: duration(data.avg_seconds) }),
			el("span", { text: "average session" }),
		]),
		el("div", {}, [
			el("b", { text: number(data.engaged_visitors) }),
			el("span", { text: `engaged (${engaged_share(data)} of uniques)` }),
		]),
		el("div", {}, [
			el("b", { text: played_share(data) }),
			el("span", { text: "played (of landing visitors)" }),
		]),
		el("div", {}, [
			el("b", { text: data.range }),
			el("span", { text: `${data.from} → ${data.to}` }),
		]),
	]);
	const tables = el("div", { class: "tables" }, [
		card("Landing page", [table("Path", data.breakdowns.path)]),
		card("Session length", [
			table("Length", data.session_length, TIME_COLUMNS),
		]),
		card("Time on page", [table("Path", data.time_on_path, TIME_COLUMNS)]),
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
				" distinct people over the range. Bots are dropped by user agent." +
				" Duration comes from a heartbeat the page sends every 30 s while it" +
				" is visible, carrying nothing but which page it is; a session is the" +
				" 30-second slots it beat in, so a visitor whose browser blocks the" +
				" beacon still counts as a view and a unique, but not as engaged." +
				" Played is the share of landing-page visitors who opened the game;" +
				" with the engaged share it is what separates people from scanners.",
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
