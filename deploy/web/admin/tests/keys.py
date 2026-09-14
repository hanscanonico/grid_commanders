"""A throwaway RSA key pair, so the Access check can be tested for real.

Generated once per process and never written to disk: it exists to sign a
token the way Cloudflare would, and to hand back the JWKS the server would
have fetched from the team's certs endpoint.
"""

from __future__ import annotations

import functools
from datetime import datetime, timedelta, timezone

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

from admin.access import KeyCache

KID = "test-key-1"


@functools.lru_cache(maxsize=1)
def private_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def jwks() -> dict[str, dict]:
    key = jwt.algorithms.RSAAlgorithm.to_jwk(private_key().public_key(), as_dict=True)
    key.update({"kid": KID, "alg": "RS256", "use": "sig"})
    return {KID: key}


class FakeKeyCache(KeyCache):
    """The real cache with its one network call replaced."""

    def __init__(self, keys: dict[str, dict] | None = None, **kwargs) -> None:
        super().__init__(**kwargs)
        self.keys = jwks() if keys is None else keys
        self.fetches = 0

    def fetch(self, url: str) -> dict[str, dict]:
        self.fetches += 1
        return self.keys


def token(
    aud: str = "test-aud",
    email: str = "owner@example.com",
    expires_in: int = 3600,
    kid: str = KID,
    key=None,
    now: datetime | None = None,
    not_before: bool = False,
) -> str:
    moment = now or datetime.now(timezone.utc)
    claims = {
        "aud": aud,
        "email": email,
        "sub": "abc123",
        "iat": int(moment.timestamp()),
        "exp": int((moment + timedelta(seconds=expires_in)).timestamp()),
    }
    if not_before:
        claims["nbf"] = int(moment.timestamp())
    return jwt.encode(
        claims,
        key or private_key(),
        algorithm="RS256",
        headers={"kid": kid},
    )
