"""Isolated integration tests: python3 -m unittest discover -s scripts -p 'test_*.py'."""
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

SCRIPT = Path(__file__).with_name("service.sh")

# The original on-disk format, with no API metadata.
LEGACY = {
    "address": "vpn.example.com", "port": 8443,
    "users": [{"id": "12345678-1234-4234-8234-123456789abc", "encryption": "none", "flow": "xtls-rprx-vision"}],
    "streamSettings": {"network": "raw", "security": "reality", "realitySettings": {
        "fingerprint": "chrome", "serverName": "www.cloudflare.com", "publicKey": "fixture-public-key",
        "shortId": "aabb", "spiderX": "/"}},
}


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {"PATH": os.environ["PATH"], "BORIS_ROOT": str(self.root),
                    "BASE_DIR": str(self.root / "base"), "PROFILE_DIR": str(self.root / "profiles"),
                    "SECRETS_DIR": str(self.root / "secrets"), "ENV_FILE": str(self.root / "client.env"),
                    "BACKUP_DIR": str(self.root / "backups"), "LOG": "/unwritable/no-log"}
        (self.root / "secrets").mkdir()
        for filename, value in {"uuid": LEGACY["users"][0]["id"], "public.key": "fixture-public-key", "short-id": "aabb"}.items():
            (self.root / "secrets" / filename).write_text(value + "\n")
        (self.root / "client.env").write_text("VLESS_PUBLIC_HOST='vpn.example.com'\nVLESS_PORT='8443'\n")

    def call(self, *args, code=None):
        result = subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                                capture_output=True, text=True, timeout=10)
        data = json.loads(result.stdout)
        self.assertEqual(result.stderr, "")
        if code:
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(data["code"], code)
        else:
            self.assertEqual(result.returncode, 0, data)
        return data

    def test_lifecycle(self):
        result = self.call("--create-client", "--name", "phone", "--format", "json")
        client = result["client"]
        self.assertEqual(client["id"], "phone")
        self.assertEqual(client["config"]["users"][0]["id"], LEGACY["users"][0]["id"])
        self.assertEqual(client["port"], 8443)
        self.assertIsNotNone(client["created"])
        self.assertEqual((self.root / "profiles/phone.json").stat().st_mode & 0o777, 0o600)
        self.call("--create-client", "--name", "phone", code="CONFLICT")
        changed = self.call("--update-client", "--name", "phone", "--new-name", "tablet",
                            "--transport", "xhttp", "--expiry", "2030-01-02")["client"]
        self.assertEqual(changed["flow"], "")
        self.assertEqual(changed["expiry"], "2030-01-02")
        query = parse_qs(urlsplit(changed["connectionString"]).query)
        self.assertEqual(query["type"], ["xhttp"])
        self.assertEqual(query["path"], ["/xhttp"])
        self.call("--get-client", "--name", "phone", code="NOT_FOUND")
        copied = self.call("--copy-client", "--name", "tablet", "--new-name", "laptop")["client"]
        self.assertEqual(copied["config"], changed["config"])
        self.call("--copy-client", "--name", "tablet", "--new-name", "laptop", code="CONFLICT")
        self.assertEqual(self.call("--list-clients")["total"], 2)
        self.assertEqual(self.call("--get-client", "--name", "laptop"), copied)
        status = self.call("--status")
        self.assertEqual(status["server"]["status"], "unknown")
        self.assertIsNone(status["clients"]["active"])
        self.assertEqual(status["traffic"], {"today": None, "total": None})
        self.call("--update-client", "--name", "tablet", "--expiry", "null")
        self.assertIsNone(self.call("--get-client", "--name", "tablet")["expiry"])
        self.assertEqual(self.call("--delete-client", "--name", "tablet"), {"success": True})
        self.call("--delete-client", "--name", "tablet", code="NOT_FOUND")
        self.assertFalse((self.root / "backups").exists())

    def test_expiry_days(self):
        operations = [
            ("--create-client", "--name", "days"),
            ("--update-client", "--name", "days"),
            ("--copy-client", "--name", "days", "--new-name", "days-copy"),
        ]
        for args, days in zip(operations, (1, 30, 365)):
            with self.subTest(action=args[0], days=days):
                before = dt.datetime.now(dt.timezone.utc)
                client = self.call(*args, "--expiry", str(days))["client"]
                after = dt.datetime.now(dt.timezone.utc)
                self.assertTrue(client["expiry"].endswith("Z"))
                expiry = dt.datetime.fromisoformat(client["expiry"].replace("Z", "+00:00"))
                self.assertLessEqual(before + dt.timedelta(days=days), expiry)
                self.assertLessEqual(expiry, after + dt.timedelta(days=days))
                stored = self.call("--get-client", "--name", client["name"])
                self.assertEqual(stored["expiry"], client["expiry"])
        for args in [("--create-client", "--name", "zero"),
                     ("--update-client", "--name", "days"),
                     ("--copy-client", "--name", "days-copy", "--new-name", "zero-copy")]:
            client = self.call(*args, "--expiry", "0")["client"]
            self.assertIsNone(client["expiry"])
            self.assertIsNone(self.call("--get-client", "--name", client["name"])["expiry"])
        for value in ("-1", "1.5", "not-days", "999999999999999999999999"):
            self.call("--update-client", "--name", "days", "--expiry", value, code="VALIDATION_ERROR")
        self.assertIsNone(self.call("--get-client", "--name", "days")["expiry"])

    def test_flow_none(self):
        for transport in ("raw", "xhttp"):
            client = self.call("--create-client", "--name", transport,
                               "--transport", transport, "--flow", "none")["client"]
            self.assert_empty_flow(client)
        self.call("--update-client", "--name", "raw", "--flow", "xtls-rprx-vision")
        copied = self.call("--copy-client", "--name", "raw", "--new-name", "copy-none",
                           "--flow", "none")["client"]
        self.assert_empty_flow(copied)
        updated = self.call("--update-client", "--name", "raw", "--flow", "none")["client"]
        self.assert_empty_flow(updated)
        self.assert_empty_flow(self.call("--get-client", "--name", "raw"))

    def assert_empty_flow(self, client):
        self.assertEqual(client["flow"], "")
        self.assertEqual(client["config"]["users"][0]["flow"], "")
        self.assertNotIn("flow", parse_qs(urlsplit(client["connectionString"]).query, keep_blank_values=True))

    def test_legacy_and_offline_operations(self):
        (self.root / "profiles").mkdir()
        (self.root / "profiles/legacy.json").write_text(json.dumps(LEGACY))
        (self.root / "client.env").unlink()
        result = self.call("--get-client", "--name", "legacy")
        self.assertEqual(result["config"], LEGACY)
        self.assertIsNone(result["created"])
        self.assertEqual(self.call("--list-clients")["serverInfo"]["port"], 8443)
        self.call("--copy-client", "--name", "legacy", "--new-name", "copy")

    def test_argument_validation(self):
        invalid = [[], ["--wat"], ["--get-client"], ["--get-client", "--name"],
                   ["--get-client", "--name", "--status"], ["--status", "--list-clients"],
                   ["--status", "--format", "text"], ["--status", "--name", "x"],
                   ["--copy-client", "--name", "x"],
                   ["--create-client", "--name", "x", "--transport", "tcp"],
                   ["--create-client", "--name", "x", "--expiry", "2030-02-30"],
                   ["--create-client", "--name", "x", "--flow", "bogus"],
                   ["--create-client", "--name", "x", "--transport", "xhttp", "--flow", "xtls-rprx-vision"]]
        # No arguments intentionally starts the original interactive mode.
        for args in invalid[1:]:
            with self.subTest(args=args):
                self.call(*args, code="VALIDATION_ERROR")
        for name in ("../escape", "a/b", "a.b", "-x", "", "a" * 65, "é"):
            self.call("--create-client", "--name", name, code="VALIDATION_ERROR")

    def test_untrusted_env_and_symlink(self):
        marker = self.root / "executed"
        (self.root / "client.env").write_text("VLESS_PUBLIC_HOST='$(touch " + str(marker) + ")'\n")
        self.call("--create-client", "--name", "x", code="VALIDATION_ERROR")
        self.assertFalse(marker.exists())
        (self.root / "profiles/link.json").symlink_to(self.root / "client.env")
        self.call("--get-client", "--name", "link", code="SCRIPT_ERROR")
        (self.root / "profiles/broken.json").write_text("not json")
        self.call("--get-client", "--name", "broken", code="SCRIPT_ERROR")

    def test_environment_precedence_and_uri_escaping(self):
        self.env.update(VLESS_PUBLIC_HOST="2001:db8::1", XHTTP_PATH='/a path?x="yes"',
                        XHTTP_HOST="cdn.example.com", VLESS_PORT="9443")
        result = self.call("--create-client", "--name", "ipv6", "--transport", "xhttp")["client"]
        uri = urlsplit(result["connectionString"])
        self.assertEqual(uri.hostname, "2001:db8::1")
        self.assertEqual(uri.port, 9443)
        self.assertEqual(parse_qs(uri.query)["path"], ['/a path?x="yes"'])

    def test_missing_configuration_and_no_secret_mutation(self):
        before = {p.name: p.read_bytes() for p in (self.root / "secrets").iterdir()}
        self.call("--create-client", "--name", "one")
        self.call("--copy-client", "--name", "one", "--new-name", "two")
        self.call("--update-client", "--name", "one", "--new-name", "two", code="CONFLICT")
        self.call("--delete-client", "--name", "two")
        self.assertEqual(before, {p.name: p.read_bytes() for p in (self.root / "secrets").iterdir()})
        for p in (self.root / "secrets").iterdir():
            p.unlink()
        self.call("--create-client", "--name", "missing", code="VALIDATION_ERROR")
        self.call("--update-client", "--name", "one", "--flow", "")
        self.assertEqual(self.call("--get-client", "--name", "one")["flow"], "")

    def test_concurrent_create(self):
        commands = [subprocess.Popen(["bash", str(SCRIPT), "--create-client", "--name", "race"],
                    env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(4)]
        results = [json.loads(p.communicate(timeout=10)[0]) for p in commands]
        self.assertEqual(sum(r.get("success", False) for r in results), 1)
        self.assertEqual(sum(r.get("code") == "CONFLICT" for r in results), 3)


if __name__ == "__main__":
    unittest.main()
