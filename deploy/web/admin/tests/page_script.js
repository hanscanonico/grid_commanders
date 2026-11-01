// Runs the page's real script against a stub DOM and a fetch that each scenario
// answers by hand, so answers can land in the order a slow PostHog puts them in.
// test_page_script.py runs this file and reads the exit code.
"use strict";

const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const SCRIPT = fs.readFileSync(
	path.join(__dirname, "..", "admin", "static", "admin.js"),
	"utf8",
);

class StubNode {
	constructor() {
		this.kids = [];
		this.own = "";
		this.attrs = {};
	}
	get text() {
		return [this.own, ...this.kids.map((kid) => kid.text)].join(" ");
	}
	set textContent(value) {
		this.own = value;
	}
	setAttribute(key, value) {
		this.attrs[key] = value;
	}
	appendChild(kid) {
		this.kids.push(kid);
	}
	replaceChildren(...kids) {
		this.kids = kids;
	}
	addEventListener(_name, listener) {
		this.click = listener;
	}
}

const settled = () => new Promise((resolve) => setImmediate(resolve));

const PANELS = [
	{ slug: "players", name: "Players" },
	{ slug: "traffic", name: "Server traffic" },
];
const players = (range) => ({
	configured: true,
	visits: 1,
	game_opens: 1,
	played: 1,
	finished: 1,
	measured_sessions: 0,
	median_seconds: 0,
	range,
	from: "a",
	to: "b",
	fetched_at: "t",
	daily: [],
	pages: [],
	countries: [],
	referrers: [],
	devices: [],
	modes: [],
	maps: [],
	missions: [],
});
const traffic = (range) => ({
	views: 1,
	uniques: 1,
	avg_seconds: 1,
	engaged_visitors: 1,
	played_uniques: 1,
	landing_uniques: 1,
	range,
	from: "a",
	to: "b",
	breakdowns: {
		path: [],
		country: [],
		referrer_host: [],
		device: [],
		utm_source: [],
		utm_medium: [],
		utm_campaign: [],
	},
	session_length: [],
	time_on_path: [],
	daily: [],
});

// The page after its panel list arrived, with the first panel's load in flight.
async function openPage() {
	const nodes = {
		body: new StubNode(),
		panels: new StubNode(),
		ranges: new StubNode(),
	};
	const asked = [];
	vm.runInNewContext(SCRIPT, {
		console,
		document: {
			getElementById: (id) => nodes[id],
			createElement: () => new StubNode(),
			createElementNS: () => new StubNode(),
		},
		fetch: (url) =>
			new Promise((resolve, reject) => asked.push({ url, resolve, reject })),
	});
	const answer = async (index, data) => {
		asked[index].resolve({ ok: true, status: 200, json: async () => data });
		await settled();
	};
	await answer(0, PANELS);
	return {
		shown: () => nodes.body.text,
		answer,
		refuse: async (index, status) => {
			asked[index].resolve({ ok: false, status, json: async () => ({}) });
			await settled();
		},
		drop: async (index) => {
			asked[index].reject(new Error("network down"));
			await settled();
		},
		click: (nav, label) =>
			nodes[nav].kids.find((button) => button.own === label).click(),
	};
}

const SCENARIOS = {
	"a late answer does not draw over the panel the reader moved to": async () => {
		const page = await openPage();
		page.click("panels", "Server traffic");
		await page.answer(2, traffic("7d"));
		await page.answer(1, players("7d"));
		assert.match(page.shown(), /pageviews/);
		assert.doesNotMatch(page.shown(), /Could not load/);
	},
	"a late answer does not end the wait for the latest": async () => {
		const page = await openPage();
		page.click("panels", "Server traffic");
		await page.answer(1, players("7d"));
		assert.match(page.shown(), /Loading/);
		await page.answer(2, traffic("7d"));
		assert.match(page.shown(), /pageviews/);
	},
	"an older range does not draw over a newer one": async () => {
		const page = await openPage();
		page.click("ranges", "90d");
		await page.answer(2, players("90d"));
		await page.answer(1, players("7d"));
		assert.match(page.shown(), /90d/);
		assert.doesNotMatch(page.shown(), /7d/);
	},
	"a late failure does not replace a drawn panel": async () => {
		const page = await openPage();
		page.click("panels", "Server traffic");
		await page.answer(2, traffic("7d"));
		await page.drop(1);
		assert.match(page.shown(), /pageviews/);
	},
	"a failed latest load says so, whatever lands after it": async () => {
		const page = await openPage();
		page.click("panels", "Server traffic");
		await page.refuse(2, 502);
		await page.answer(1, players("7d"));
		assert.match(page.shown(), /HTTP 502/);
	},
	"the same button twice draws once the second answer lands": async () => {
		const page = await openPage();
		page.click("panels", "Players");
		await page.answer(1, players("7d"));
		assert.match(page.shown(), /Loading/);
		await page.answer(2, players("7d"));
		assert.match(page.shown(), /opened the game/);
	},
};

(async () => {
	let failed = 0;
	for (const [name, scenario] of Object.entries(SCENARIOS)) {
		try {
			await scenario();
		} catch (error) {
			failed += 1;
			console.error(`${name}: ${error.message}`);
		}
	}
	process.exitCode = failed === 0 ? 0 : 1;
})();
