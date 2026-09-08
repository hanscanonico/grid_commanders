#!/usr/bin/env python3
"""Audits what a crawler sees of gridcommanders.com.

Usage:  tools/check_web_site.py [exported-site-dir]

With no argument it reads the sources — `deploy/web/site/` and the Web preset's
`html/head_include` — which is why `make check` can run it with no export in
hand. Given the tree `make export-web` (or the Docker image) built, it also
opens `play/index.html`, so the exported game page is held to the same bar as
the preset key it comes from.

Every assertion is about the *served* bytes, never about how they were authored:
the HTML is regexed rather than parsed against a template, so rewriting the page
by hand, from a generator or in another editor cannot quietly drop a tag.

"Advance Wars" is held to body copy and the meta description — CLAUDE.md's legal
note keeps it out of the title, the headings and the social titles.
"""

import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SITE = "https://gridcommanders.com"
SITEMAP_URLS = [SITE + "/", SITE + "/play/"]
OG_SIZE = (1200, 630)
DESCRIPTION_MAX = 160
FORBIDDEN = "advance wars"

ROOT = Path(__file__).resolve().parent.parent
SOURCE_SITE = ROOT / "deploy" / "web" / "site"
PRESETS = ROOT / "export_presets.cfg"

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def meta(html: str, attr: str, name: str) -> str | None:
    pattern = r'<meta\s+%s="%s"\s+content="([^"]*)"' % (attr, re.escape(name))
    found = re.search(pattern, html, re.IGNORECASE)
    return found.group(1) if found else None


def canonical(html: str) -> str | None:
    found = re.search(r'<link\s+rel="canonical"\s+href="([^"]*)"', html, re.IGNORECASE)
    return found.group(1) if found else None


def check_description(html: str, where: str) -> None:
    """A result page truncates past ~160 characters, so a longer one loses its ending."""
    description = meta(html, "name", "description")
    if not description:
        fail("%s: no meta description" % where)
    elif len(description) > DESCRIPTION_MAX:
        fail(
            "%s: the description is %d chars (max %d)"
            % (where, len(description), DESCRIPTION_MAX)
        )


def head_include() -> str:
    """The Web preset's html/head_include, unescaped back to the HTML it emits."""
    text = PRESETS.read_text()
    found = re.search(r'^html/head_include="((?:[^"\\]|\\.)*)"$', text, re.MULTILINE)
    if not found:
        fail("export_presets.cfg: the Web preset has no html/head_include")
        return ""
    return found.group(1).replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def check_game_head(html: str, where: str) -> None:
    check_description(html, where)
    href = canonical(html)
    if href != SITE + "/play/":
        fail("%s: the game page's canonical is %r, expected %s/play/" % (where, href, SITE))
    if re.search(r'<meta\s+name="robots"[^>]*noindex', html, re.IGNORECASE):
        fail("%s: the game page is noindex — it is meant to be found" % where)


def check_landing(html: str, where: str) -> None:
    title = re.search(r"<title>([^<]*)</title>", html, re.IGNORECASE)
    if not title or not title.group(1).strip():
        fail("%s: no <title>" % where)

    check_description(html, where)

    href = canonical(html)
    if href != SITE + "/":
        fail("%s: canonical is %r, expected %s/" % (where, href, SITE))

    for tag in ("og:title", "og:description", "og:image"):
        if not meta(html, "property", tag):
            fail("%s: no %s" % (where, tag))

    image = meta(html, "property", "og:image") or ""
    if not image.startswith(SITE + "/"):
        fail("%s: og:image %r is not an absolute URL on %s" % (where, image, SITE))

    blocks = re.findall(
        r'<script type="application/ld\+json">(.*?)</script>',
        html,
        re.IGNORECASE | re.DOTALL,
    )
    if not blocks:
        fail("%s: no JSON-LD block" % where)
    for block in blocks:
        try:
            data = json.loads(block)
        except json.JSONDecodeError as error:
            fail("%s: the JSON-LD block does not parse — %s" % (where, error))
            continue
        if data.get("@type") != "VideoGame":
            fail(
                "%s: the JSON-LD block is a %r, expected a VideoGame"
                % (where, data.get("@type"))
            )

    if not re.search(r'href="/play/"', html):
        fail("%s: nothing links to /play/" % where)

    named = [title.group(1) if title else ""]
    named += re.findall(r"<h[1-6][^>]*>(.*?)</h[1-6]>", html, re.IGNORECASE | re.DOTALL)
    named.append(meta(html, "property", "og:title") or "")
    named.append(meta(html, "name", "twitter:title") or "")
    for text in named:
        if FORBIDDEN in text.lower():
            fail(
                "%s: %r names Advance Wars — body copy and the description only"
                % (where, text.strip())
            )


def check_og_image(path: Path) -> None:
    if not path.is_file():
        fail("%s: missing" % path)
        return
    header = path.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        fail("%s: not a PNG" % path)
        return
    size = struct.unpack(">II", header[16:24])
    if size != OG_SIZE:
        fail("%s: is %dx%d, the sharing card wants %dx%d" % (path, *size, *OG_SIZE))


def check_robots(path: Path) -> None:
    if not path.is_file():
        fail("%s: missing" % path)
        return
    text = path.read_text()
    if "Sitemap: %s/sitemap.xml" % SITE not in text:
        fail("%s: does not name %s/sitemap.xml" % (path, SITE))
    if not re.search(r"^Allow: /$", text, re.MULTILINE):
        fail("%s: does not allow crawling" % path)


def check_sitemap(path: Path) -> None:
    if not path.is_file():
        fail("%s: missing" % path)
        return
    try:
        root = ET.fromstring(path.read_text())
    except ET.ParseError as error:
        fail("%s: does not parse — %s" % (path, error))
        return
    found = [node.text for node in root.iter("{http://www.sitemaps.org/schemas/sitemap/0.9}loc")]
    if found != SITEMAP_URLS:
        fail("%s: lists %r, expected %r" % (path, found, SITEMAP_URLS))


def main(argv: list[str]) -> int:
    landing = SOURCE_SITE / "index.html"
    if not landing.is_file():
        fail("%s: missing" % landing)
    else:
        check_landing(landing.read_text(), str(landing))
    check_og_image(SOURCE_SITE / "og-battle.png")
    check_robots(SOURCE_SITE / "robots.txt")
    check_sitemap(SOURCE_SITE / "sitemap.xml")
    check_game_head(head_include(), "export_presets.cfg html/head_include")

    if argv:
        exported = Path(argv[0])
        for name in ("index.html", "og-battle.png", "robots.txt", "sitemap.xml"):
            if not (exported / name).is_file():
                fail("%s: the exported site has no %s" % (exported, name))
        game = exported / "play" / "index.html"
        if not game.is_file():
            fail("%s: the exported site has no play/index.html" % exported)
        else:
            check_game_head(game.read_text(), str(game))

    for message in failures:
        print("check-web-site: " + message, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
