"""One proxied request turned into the row the store keeps.

Everything here is a pure function of strings, so the whole privacy promise —
no IP, no user agent past a class and a verdict — is readable in one file and
testable without a socket.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from urllib.parse import parse_qs, urlsplit

# Substrings, lowercased, matched anywhere in the user agent. The named
# crawlers are the ones that actually reach a small site; the generic words
# catch the rest, including every library someone points at a URL by hand.
BOT_MARKERS: tuple[str, ...] = (
    "bot",
    "crawler",
    "spider",
    "slurp",
    "curl",
    "wget",
    "python-requests",
    "headless",
    "lighthouse",
    "googlebot",
    "bingbot",
    "yandex",
    "baiduspider",
    "duckduckbot",
    "applebot",
    "facebookexternalhit",
    "twitterbot",
    "linkedinbot",
    "discordbot",
    "telegrambot",
    "whatsapp",
    "slackbot",
    "pingdom",
    "uptimerobot",
    "ahrefs",
    "semrush",
    "mj12",
    "dotbot",
    "petalbot",
    "gptbot",
    "ccbot",
    "claudebot",
    "perplexitybot",
    "chatgpt-user",
    "scrapy",
    "http-client",
    "okhttp",
    "go-http-client",
    "libwww-perl",
    "java/",
    "axios",
    "node-fetch",
    "phantomjs",
    "puppeteer",
    "playwright",
    "monitoring",
    "preview",
)

# The page URLs worth a pageview, and what each is stored as. Anything else —
# an asset, a 404, a directory the export does not have — is not a page.
PAGE_PATHS: dict[str, str] = {
    "/": "/",
    "/index.html": "/",
    "/play": "/play/",
    "/play/": "/play/",
    "/play/index.html": "/play/",
}

_PHONE_MARKERS: tuple[str, ...] = ("iphone", "ipod", "windows phone", "mobi")
_TABLET_MARKERS: tuple[str, ...] = ("ipad", "tablet", "kindle", "silk", "playbook")

UTM_KEYS: tuple[str, ...] = ("utm_source", "utm_medium", "utm_campaign")

# Every breakdown key a visitor can choose the text of — the referrer host and
# the three UTM fields — is cut to this. A real host and a real campaign are far
# shorter, and the aggregates are kept forever: a stranger must not be able to
# decide how wide a stored row is.
MAX_KEY_CHARS = 64

# A beat carries one known path and nothing else, so a few hundred bytes is
# already generous. nginx caps the request body at the same order of size; this
# is the collector's own refusal, for the day it is reached another way.
MAX_BEAT_BYTES = 256


@dataclass(frozen=True)
class Hit:
    """A page request, with nothing left in it that names a person."""

    path: str
    country: str
    referrer_host: str
    device: str
    utm_source: str
    utm_medium: str
    utm_campaign: str
    visitor: str


def is_bot(ua: str) -> bool:
    """True when the user agent names a crawler, a library or a monitor."""
    if not ua:
        # A browser always sends one. A blank agent is a script.
        return True
    lowered = ua.lower()
    return any(marker in lowered for marker in BOT_MARKERS)


def device_class(ua: str) -> str:
    """`phone`, `tablet` or `desktop` — the three the panel breaks down by."""
    lowered = (ua or "").lower()
    if any(marker in lowered for marker in _TABLET_MARKERS):
        return "tablet"
    # Android without "mobi" is the tablet convention Google asks for, so the
    # phone test is the marker list plus that pair rather than "android".
    if "android" in lowered:
        return "phone" if "mobi" in lowered else "tablet"
    if any(marker in lowered for marker in _PHONE_MARKERS):
        return "phone"
    return "desktop"


def referrer_host(referer: str, own_host: str) -> str:
    """The sending site's host, or "" for a direct visit or our own pages."""
    if not referer:
        return ""
    split = urlsplit(referer if "//" in referer else "//" + referer)
    host = split.hostname or ""
    host = host.lower().removeprefix("www.")
    if not host or host == (own_host or "").lower().removeprefix("www."):
        return ""
    return host[:MAX_KEY_CHARS]


def utm(query: str) -> tuple[str, str, str]:
    """The three UTM values in a query string, each "" when absent."""
    parsed = parse_qs(query or "", keep_blank_values=False)
    values: list[str] = []
    for key in UTM_KEYS:
        found = parsed.get(key, [""])[0].strip().lower()
        values.append(found[:MAX_KEY_CHARS])
    return values[0], values[1], values[2]


def visitor_hash(secret: str, day: str, ip: str, ua: str) -> str:
    """A visitor id that dies at midnight.

    The day is part of the digest, so the same person is a different id
    tomorrow and nothing can follow them across days. The IP goes in and never
    comes out: the digest is all that is stored.
    """
    material = f"{secret}|{day}|{ip}|{ua}".encode()
    return hashlib.sha256(material).hexdigest()


def normalise_path(uri: str) -> str:
    """The stored path for a request URI, or "" when it is not a page."""
    path = urlsplit(uri or "").path
    if not path:
        return ""
    return PAGE_PATHS.get(path, "")


def query_of(uri: str) -> str:
    """The query string of a request URI, without the `?`."""
    return urlsplit(uri or "").query


def beat_from(
    headers: dict[str, str], body: bytes, secret: str, day: str
) -> Hit | None:
    """The row for one heartbeat, or None when it is not one we count.

    A beat says only which page it came from. Everything about the person —
    the day's visitor digest — is derived from the same headers a pageview
    uses, so a client cannot name itself even if it tries.
    """
    if not body or len(body) > MAX_BEAT_BYTES:
        return None
    try:
        sent_body = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return None
    if not isinstance(sent_body, dict):
        return None
    asked = sent_body.get("path")
    if not isinstance(asked, str):
        return None
    path = normalise_path(asked)
    if not path:
        return None
    sent = {name.lower(): value or "" for name, value in headers.items()}
    ua = sent.get("user-agent", "")
    if is_bot(ua):
        return None
    return Hit(
        path=path,
        country="",
        referrer_host="",
        device="",
        utm_source="",
        utm_medium="",
        utm_campaign="",
        visitor=visitor_hash(secret, day, sent.get("cf-connecting-ip", ""), ua),
    )


def from_headers(
    headers: dict[str, str], secret: str, day: str, site_host: str
) -> Hit | None:
    """The row for one mirrored request, or None when it is not a pageview."""
    # Header names are case-insensitive on the wire, so read them that way
    # rather than trusting the casing nginx happened to send.
    sent = {name.lower(): value or "" for name, value in headers.items()}
    if (sent.get("x-original-method") or "GET").upper() != "GET":
        return None
    uri = sent.get("x-original-uri", "")
    path = normalise_path(uri)
    if not path:
        return None
    ua = sent.get("user-agent", "")
    if is_bot(ua):
        return None
    ip = sent.get("cf-connecting-ip", "")
    source, medium, campaign = utm(query_of(uri))
    return Hit(
        path=path,
        country=(sent.get("cf-ipcountry") or "XX").upper()[:2],
        referrer_host=referrer_host(sent.get("referer", ""), site_host),
        device=device_class(ua),
        utm_source=source,
        utm_medium=medium,
        utm_campaign=campaign,
        visitor=visitor_hash(secret, day, ip, ua),
    )
