import unittest
from datetime import datetime, timedelta, timezone

from cryptography.hazmat.primitives.asymmetric import rsa

from admin import access
from tests import keys

NOW = datetime(2026, 9, 14, 12, 0, tzinfo=timezone.utc)
TEAM = "gridcommanders"
AUD = "test-aud"


class VerifyTests(unittest.TestCase):
    def setUp(self):
        self.cache = keys.FakeKeyCache()

    def verify(self, header_value, team=TEAM, aud=AUD, now=NOW):
        headers = {} if header_value is None else {access.HEADER: header_value}
        return access.verify(headers, team, aud, now, cache=self.cache)

    def test_a_valid_token_yields_the_email(self):
        signed = keys.token(now=NOW)
        self.assertEqual(self.verify(signed), "owner@example.com")

    def test_a_lowercased_header_is_the_same_header(self):
        signed = keys.token(now=NOW)
        self.assertEqual(
            access.verify(
                {access.HEADER.lower(): signed}, TEAM, AUD, NOW, cache=self.cache
            ),
            "owner@example.com",
        )

    def test_the_wrong_audience_fails(self):
        self.assertIsNone(self.verify(keys.token(aud="someone-elses-app", now=NOW)))

    def test_an_expired_token_fails(self):
        signed = keys.token(now=NOW - timedelta(hours=2), expires_in=3600)
        self.assertIsNone(self.verify(signed))

    def test_a_token_not_yet_valid_fails(self):
        signed = keys.token(now=NOW + timedelta(hours=1), not_before=True)
        self.assertIsNone(self.verify(signed))

    def test_a_token_from_another_key_fails(self):
        stranger = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.assertIsNone(self.verify(keys.token(key=stranger, now=NOW)))

    def test_a_tampered_token_fails(self):
        signed = keys.token(now=NOW)
        head, payload, signature = signed.split(".")
        self.assertIsNone(self.verify(f"{head}.{payload}.{signature[:-4]}AAAA"))

    def test_an_unknown_kid_fails_after_a_refetch(self):
        self.assertIsNone(self.verify(keys.token(kid="rotated-away", now=NOW)))
        self.assertGreaterEqual(self.cache.fetches, 1)

    def test_a_missing_token_fails(self):
        self.assertIsNone(self.verify(None))
        self.assertIsNone(self.verify(""))

    def test_garbage_is_not_a_token(self):
        self.assertIsNone(self.verify("not-a-jwt"))

    def test_unset_env_fails_closed(self):
        signed = keys.token(now=NOW)
        self.assertIsNone(self.verify(signed, team=""))
        self.assertIsNone(self.verify(signed, aud=""))
        self.assertIsNone(self.verify(signed, team="", aud=""))

    def test_an_unconfigured_check_never_reaches_the_network(self):
        self.verify(keys.token(now=NOW), team="")
        self.assertEqual(self.cache.fetches, 0)


class KeyCacheTests(unittest.TestCase):
    def test_a_known_kid_is_served_from_the_cache(self):
        cache = keys.FakeKeyCache()
        url = access.CERTS_URL.format(team=TEAM)
        cache.key_for(url, keys.KID, NOW.timestamp())
        cache.key_for(url, keys.KID, NOW.timestamp() + 60)
        self.assertEqual(cache.fetches, 1)

    def test_the_cache_expires(self):
        cache = keys.FakeKeyCache(ttl=10)
        url = access.CERTS_URL.format(team=TEAM)
        cache.key_for(url, keys.KID, NOW.timestamp())
        cache.key_for(url, keys.KID, NOW.timestamp() + 11)
        self.assertEqual(cache.fetches, 2)

    def test_an_unknown_kid_refetches_before_the_ttl(self):
        cache = keys.FakeKeyCache()
        url = access.CERTS_URL.format(team=TEAM)
        cache.key_for(url, keys.KID, NOW.timestamp())
        self.assertIsNone(cache.key_for(url, "other", NOW.timestamp() + 1))
        self.assertEqual(cache.fetches, 2)

    def test_the_certs_url_is_the_teams(self):
        self.assertEqual(
            access.CERTS_URL.format(team=TEAM),
            "https://gridcommanders.cloudflareaccess.com/cdn-cgi/access/certs",
        )


if __name__ == "__main__":
    unittest.main()
