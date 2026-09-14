"""The Cloudflare Access check that stands in front of every `/admin` route.

Access terminates the login at Cloudflare's edge and hands the origin a signed
RS256 token in `Cf-Access-Jwt-Assertion`. This module is the only thing that
believes it. It fails closed: no team, no audience, no token, or anything the
signature does not cover, and the answer is None.

The token is never logged, in whole or in part — it is a bearer credential for
as long as it lives.
"""

from __future__ import annotations

import json
import threading
import urllib.request
from datetime import datetime

import jwt

CERTS_URL = "https://{team}.cloudflareaccess.com/cdn-cgi/access/certs"
HEADER = "Cf-Access-Jwt-Assertion"
JWKS_TTL_SECONDS = 12 * 3600
FETCH_TIMEOUT_SECONDS = 5

NOT_CONFIGURED = "admin: Cloudflare Access not configured"
DENIED = "admin: Cloudflare Access required"


class KeyCache:
    """The team's signing keys, fetched once and kept for 12 hours.

    An unknown `kid` refetches immediately rather than waiting out the TTL:
    that is what a key rotation looks like from here, and a rotation should
    cost one request, not half a day of 403s.
    """

    def __init__(self, ttl: float = JWKS_TTL_SECONDS) -> None:
        self._ttl = ttl
        self._lock = threading.Lock()
        self._keys: dict[str, dict] = {}
        self._fetched_at: float = 0.0

    def fetch(self, url: str) -> dict[str, dict]:
        with urllib.request.urlopen(url, timeout=FETCH_TIMEOUT_SECONDS) as response:
            document = json.loads(response.read().decode("utf-8"))
        return {key["kid"]: key for key in document.get("keys", []) if key.get("kid")}

    def key_for(self, url: str, kid: str, now: float) -> dict | None:
        with self._lock:
            stale = now - self._fetched_at > self._ttl
            if not stale and kid in self._keys:
                return self._keys[kid]
            self._keys = self.fetch(url)
            self._fetched_at = now
            return self._keys.get(kid)


_CACHE = KeyCache()


def verify(
    headers: dict[str, str],
    team: str,
    aud: str,
    now: datetime,
    cache: KeyCache | None = None,
) -> str | None:
    """The signed-in email behind a request, or None to refuse it."""
    if not team or not aud:
        return None
    token = _header(headers, HEADER)
    if not token:
        return None
    try:
        kid = jwt.get_unverified_header(token).get("kid", "")
        if not kid:
            return None
        jwk = (cache or _CACHE).key_for(
            CERTS_URL.format(team=team), kid, now.timestamp()
        )
        if jwk is None:
            return None
        claims = jwt.decode(
            token,
            key=jwt.PyJWK(jwk, algorithm="RS256").key,
            algorithms=["RS256"],
            audience=aud,
            # Every time check is made below against the `now` the caller
            # passed, so a test can move the clock and the server always reads
            # one rather than two.
            options={
                "require": ["exp", "aud"],
                "verify_exp": False,
                "verify_nbf": False,
                "verify_iat": False,
            },
        )
        moment = now.timestamp()
        if float(claims["exp"]) <= moment:
            return None
        if float(claims.get("nbf", 0)) > moment:
            return None
    except Exception:
        # Every failure is the same failure to a caller: the request is not
        # signed in. The reason stays here rather than in a log line that
        # would have to quote the token to be useful.
        return None
    return str(claims.get("email") or claims.get("sub") or "")


def _header(headers: dict[str, str], wanted: str) -> str:
    """A header by name, whatever case the proxy in front chose to send."""
    lowered = wanted.lower()
    for name, value in headers.items():
        if name.lower() == lowered:
            return value or ""
    return ""
