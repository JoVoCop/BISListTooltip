import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("publish_curseforge", TOOLS_DIR / "publish-curseforge.py")
assert spec is not None and spec.loader is not None
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)


class ReleaseTypeTest(unittest.TestCase):
    def test_plain_versions_are_releases_and_suffixes_opt_players_in(self):
        self.assertEqual(publish.release_type("v2.0.0"), "release")
        self.assertEqual(publish.release_type("v2.1.0-beta.1"), "beta")
        self.assertEqual(publish.release_type("v2.1.0-alpha"), "alpha")


class GameVersionsTest(unittest.TestCase):
    def test_reads_one_or_more_ids(self):
        self.assertEqual(publish.parse_game_versions("12345"), [12345])
        self.assertEqual(publish.parse_game_versions(" 1, 2 "), [1, 2])

    def test_rejects_anything_but_ids_and_says_how_to_find_them(self):
        for value in ["", "1.60.1", "Forever"]:
            with self.assertRaisesRegex(publish.PublishError, "--list-game-versions"):
                publish.parse_game_versions(value)


class MetadataTest(unittest.TestCase):
    def test_sends_the_markdown_changelog_and_game_versions(self):
        self.assertEqual(
            publish.metadata("v2.0.0", "BISListTooltip-v2.0.0.zip", "## v2.0.0\n* New", [12345]),
            {
                "displayName": "BISListTooltip-v2.0.0.zip",
                "changelog": "## v2.0.0\n* New",
                "changelogType": "markdown",
                "gameVersions": [12345],
                "releaseType": "release",
            },
        )


class MultipartTest(unittest.TestCase):
    def test_carries_the_metadata_field_and_the_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "BISListTooltip-v2.0.0.zip"
            zip_path.write_bytes(b"PK\x03\x04zip")
            body, content_type = publish.multipart({"metadata": json.dumps({"a": 1})}, "file", zip_path)
        boundary = content_type.split("boundary=")[1]
        self.assertTrue(content_type.startswith("multipart/form-data; "))
        self.assertIn(b'name="metadata"\r\n\r\n{"a": 1}\r\n', body)
        self.assertIn(b'name="file"; filename="BISListTooltip-v2.0.0.zip"', body)
        self.assertIn(b"PK\x03\x04zip", body)
        self.assertTrue(body.endswith(f"--{boundary}--\r\n".encode()))


if __name__ == "__main__":
    unittest.main()
