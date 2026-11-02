import base64
import importlib.util
import io
import os
import re
import shutil
import subprocess
import tempfile
import unittest
import zlib
from contextlib import redirect_stderr
from pathlib import Path
from typing import Any
from unittest import mock

TOOLS_DIR = Path(__file__).resolve().parent
REPO_DIR = TOOLS_DIR.parent

spec = importlib.util.spec_from_file_location("sync_builtin", TOOLS_DIR / "sync-builtin.py")
assert spec is not None and spec.loader is not None
sync_builtin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync_builtin)


def make_import_string(
    list_id: str = "abc",
    version: int = 20261104001,
    game: str = "forever",
    title: str = "Title",
    author: str = "Author",
    entry_line: str = "E\tMAGE\tFire\t1\thead\t1\tBest",
) -> str:
    body = f"H\t{list_id}\t{version}\t1761782400\t{game}\t{title}\t{author}\n{entry_line}"
    compressor = zlib.compressobj(wbits=-15)
    raw = compressor.compress(body.encode("utf-8")) + compressor.flush()
    return "BLT1:" + base64.b64encode(raw).decode("ascii")


def make_list(list_id: str = "abc", version: int = 20261104001, title: str = "Title") -> dict[str, Any]:
    return {
        "listId": list_id,
        "version": version,
        "publishedAt": 1761782400,
        "title": title,
        "author": "Author",
        "importString": make_import_string(list_id, version, title=title),
    }


class DecodeHeaderTest(unittest.TestCase):
    def test_decode_reads_the_h_line(self) -> None:
        header = sync_builtin.decode_import_string(make_import_string("xyz", 20261104002, title="T", author="A"))
        self.assertEqual(
            header,
            {"listId": "xyz", "version": 20261104002, "publishedAt": 1761782400,
             "game": "forever", "title": "T", "author": "A"},
        )

    def test_decode_strips_whitespace(self) -> None:
        text = make_import_string()
        broken = text[:10] + "\n \t" + text[10:] + "\r\n"
        self.assertEqual(sync_builtin.decode_import_string(broken)["listId"], "abc")

    def test_decode_rejects_bad_prefix_and_truncation(self) -> None:
        text = make_import_string()
        with self.assertRaisesRegex(sync_builtin.SyncError, "prefix"):
            sync_builtin.decode_import_string("XYZ:" + text[5:])
        with self.assertRaises(sync_builtin.SyncError):
            sync_builtin.decode_import_string(text[: len(text) // 2])
        with self.assertRaises(sync_builtin.SyncError):
            sync_builtin.decode_import_string("BLT1:!!!!")


class RenderTest(unittest.TestCase):
    def test_render_is_deterministic_and_escapes(self) -> None:
        item = make_list(title='Say "hi" \\ line\nbreak é')
        first = sync_builtin.render_builtin_lists([item])
        self.assertEqual(first, sync_builtin.render_builtin_lists([item]))
        self.assertIn('\\"', first)
        self.assertIn("\\\\", first)
        self.assertIn("\\010", first)
        self.assertIn("é", first)
        self.assertIn("20261104001", first)

    def test_committed_data_files_are_what_the_renderer_produces(self) -> None:
        lists_lua = (REPO_DIR / "Data" / "BuiltinLists.lua").read_text(encoding="utf-8")
        item_pattern = re.compile(r"^  \{\n(.*?)^  \},$", re.MULTILINE | re.DOTALL)
        field_pattern = re.compile(r'^    (\w+) = (?:"((?:[^"\\]|\\.)*)"|(\d+)),$', re.MULTILINE)
        parsed_lists: list[dict[str, Any]] = []
        for body in item_pattern.findall(lists_lua):
            parsed_lists.append({
                key: int(number) if number else sync_builtin.unescape_lua_string(text)
                for key, text, number in field_pattern.findall(body)
            })
        self.assertEqual(lists_lua, sync_builtin.render_builtin_lists(parsed_lists))

        tokens_lua = (REPO_DIR / "Data" / "Tokens.lua").read_text(encoding="utf-8")
        parsed_tokens = [
            {"tokenItemId": token_id, "rewardItemIds": rewards}
            for token_id, rewards in sync_builtin.read_generated_tokens(tokens_lua).items()
        ]
        self.assertEqual(tokens_lua, sync_builtin.render_tokens(parsed_tokens))

    def test_tokens_are_sorted(self) -> None:
        text = sync_builtin.render_tokens([
            {"tokenItemId": 20, "rewardItemIds": [5, 3]},
            {"tokenItemId": 10, "rewardItemIds": [9]},
        ])
        self.assertLess(text.index("[10]"), text.index("[20]"))
        self.assertIn("{ 3, 5 }", text)

    def test_rendered_lua_loads_in_the_addon(self) -> None:
        if shutil.which("lua5.1") is None:
            self.skipTest("lua5.1 not installed")
        lists = [make_list("a", title='Q"uote'), make_list("b", 20261104002)]
        tokens = [{"tokenItemId": 10, "rewardItemIds": [9, 8]}]
        with tempfile.TemporaryDirectory() as directory:
            lists_path = Path(directory) / "lists.lua"
            tokens_path = Path(directory) / "tokens.lua"
            lists_path.write_bytes(sync_builtin.render_builtin_lists(lists).encode("utf-8"))
            tokens_path.write_bytes(sync_builtin.render_tokens(tokens).encode("utf-8"))
            script = (
                "local ns = {}\n"
                f"assert(loadfile('{lists_path}'))('addon', ns)\n"
                f"assert(loadfile('{tokens_path}'))('addon', ns)\n"
                "print(#ns.BuiltinLists, ns.BuiltinLists[1].title, ns.TokenRewards[10][1])"
            )
            result = subprocess.run(["lua5.1", "-e", script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip().split("\t"), ["2", 'Q"uote', "8"])


class SummaryTest(unittest.TestCase):
    def test_summary_reports_added_removed_updated_and_tokens(self) -> None:
        old_lists = sync_builtin.render_builtin_lists([
            make_list("keep", 20261104001, "Kept"),
            make_list("gone", 20261104001, "Gone"),
            make_list("up", 20261104001, "Up"),
        ])
        old_tokens = sync_builtin.render_tokens([{"tokenItemId": 1, "rewardItemIds": [2]}])
        new_lists = [make_list("keep", 20261104001, "Kept"), make_list("up", 20261105002, "Up"),
                     make_list("new", 20261105001, "New")]
        new_tokens = [{"tokenItemId": 1, "rewardItemIds": [2]}, {"tokenItemId": 3, "rewardItemIds": [4]}]
        lines = sync_builtin.summarize(old_lists, new_lists, old_tokens, new_tokens)
        self.assertEqual(lines, [
            'Added: "New" (new) v2026.11.05.1',
            'Removed: "Gone" (gone)',
            'Updated: "Up" v2026.11.04.1 -> v2026.11.05.2',
            "Token mappings: +1 added, -0 removed, 0 changed",
        ])

    def test_summary_no_changes(self) -> None:
        lists = [make_list()]
        tokens = [{"tokenItemId": 1, "rewardItemIds": [2]}]
        lines = sync_builtin.summarize(
            sync_builtin.render_builtin_lists(lists), lists, sync_builtin.render_tokens(tokens), tokens)
        self.assertEqual(lines, ["No changes."])


class TokenSummaryTest(unittest.TestCase):
    def test_same_count_different_rewards_is_reported(self) -> None:
        old = sync_builtin.render_tokens([{"tokenItemId": 1, "rewardItemIds": [2]}])
        new = [{"tokenItemId": 1, "rewardItemIds": [2, 3]}]
        lines = sync_builtin.summarize("", [], old, new)
        self.assertEqual(lines, ["Token mappings: +0 added, -0 removed, 1 changed"])

    def test_removed_token_is_reported(self) -> None:
        old = sync_builtin.render_tokens([{"tokenItemId": 1, "rewardItemIds": [2]}])
        self.assertEqual(sync_builtin.summarize("", [], old, []),
                         ["Token mappings: +0 added, -1 removed, 0 changed"])


class CatalogTest(unittest.TestCase):
    CATALOG_PATH = str(REPO_DIR / "Catalog.lua")

    def current(self) -> dict[str, Any]:
        return {
            "classes": ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"],
            "slotGroups": ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs",
                           "feet", "finger", "trinket", "weapon", "main-hand", "off-hand", "two-hand", "ranged", "relic"],
        }

    def test_matching_catalog_passes(self) -> None:
        sync_builtin.check_catalog(self.current(), self.CATALOG_PATH)

    def test_catalog_mismatch_fails_with_differences(self) -> None:
        catalog = self.current()
        catalog["classes"].append("EVOKER")
        catalog["slotGroups"].remove("neck")
        with self.assertRaises(sync_builtin.SyncError) as context:
            sync_builtin.check_catalog(catalog, self.CATALOG_PATH)
        message = str(context.exception)
        self.assertIn("EVOKER", message)
        self.assertIn("neck", message)
        self.assertIn("update Catalog.lua and the fixtures first", message)

    def test_catalog_order_difference_fails(self) -> None:
        catalog = self.current()
        catalog["classes"].reverse()
        with self.assertRaises(sync_builtin.SyncError):
            sync_builtin.check_catalog(catalog, self.CATALOG_PATH)


class FormatVersionTest(unittest.TestCase):
    def test_format_version_matches_the_readme_table(self) -> None:
        table = {
            20261104001: "2026.11.04.1",
            20261231012: "2026.12.31.12",
            20240229001: "2024.02.29.1",
            5: "5",
            20261304001: "20261304001",
            20260231001: "20260231001",
            20261104000: "20261104000",
            202611041000: "202611041000",
        }
        for value, expected in table.items():
            self.assertEqual(sync_builtin.format_version(value), expected, value)


class HeaderMismatchTest(unittest.TestCase):
    def payload(self, entry: dict[str, Any]) -> dict[str, Any]:
        return {"catalog": CatalogTest().current(), "tokens": [], "lists": [entry]}

    def test_header_mismatch_fails(self) -> None:
        wrong_id = {**make_list("abc"), "listId": "other"}
        wrong_version = {**make_list("abc"), "version": 20261104009}
        wrong_game = {**make_list("abc"), "importString": make_import_string("abc", game="sod")}
        for entry in (wrong_id, wrong_version, wrong_game):
            with self.assertRaises(sync_builtin.SyncError):
                sync_builtin.build_outputs(self.payload(entry), CatalogTest.CATALOG_PATH)


class BodyValidationTest(unittest.TestCase):
    def payload(self, import_string: str) -> dict[str, Any]:
        entry = {**make_list("abc", title="Broken List"), "importString": import_string}
        return {"catalog": CatalogTest().current(), "tokens": [], "lists": [entry]}

    def test_corrupt_entry_lines_fail_naming_the_list(self) -> None:
        corrupt_lines = [
            "E\tMAGE\tFire\t1\thead\t1",
            "E\tMAGE\tFire\t1\thead\t1\tBest\textra",
            "X\tMAGE\tFire\t1\thead\t1\tBest",
            "E\tMAGE\t\t1\thead\t1\tBest",
            "E\tMAGE\t" + "x" * 33 + "\t1\thead\t1\tBest",
            "E\tMAGE\tFire\tnope\thead\t1\tBest",
            "E\tMAGE\tFire\t0\thead\t1\tBest",
            "E\tMAGE\tFire\t1\thead\t0\tBest",
        ]
        for line in corrupt_lines:
            with self.subTest(line=line):
                payload = self.payload(make_import_string("abc", title="Broken List", entry_line=line))
                with self.assertRaisesRegex(sync_builtin.SyncError, "Broken List"):
                    sync_builtin.build_outputs(payload, CatalogTest.CATALOG_PATH)

    def test_unknown_class_and_slot_lines_are_still_accepted(self) -> None:
        line = "E\tDEATHKNIGHT\tBlood\t1\tmystery\t1\tBest"
        payload = self.payload(make_import_string("abc", title="Broken List", entry_line=line))
        lists, _ = sync_builtin.build_outputs(payload, CatalogTest.CATALOG_PATH)
        self.assertEqual(lists[0]["listId"], "abc")

    def test_a_list_with_no_entries_is_valid(self) -> None:
        body = "H\tabc\t20261104001\t1761782400\tforever\tTitle\tAuthor"
        compressor = zlib.compressobj(wbits=-15)
        raw = compressor.compress(body.encode("utf-8")) + compressor.flush()
        header = sync_builtin.decode_import_string("BLT1:" + base64.b64encode(raw).decode("ascii"))
        self.assertEqual(header["listId"], "abc")


class DuplicateTest(unittest.TestCase):
    def test_duplicate_list_ids_fail(self) -> None:
        payload = {"catalog": CatalogTest().current(), "tokens": [],
                   "lists": [make_list("abc"), make_list("abc", 20261104002)]}
        with self.assertRaisesRegex(sync_builtin.SyncError, "duplicate"):
            sync_builtin.build_outputs(payload, CatalogTest.CATALOG_PATH)


class MainTest(unittest.TestCase):
    SENTINEL = "-- untouched\n"

    def assert_untouched(self, root: Path) -> None:
        for name in ("BuiltinLists.lua", "Tokens.lua"):
            self.assertEqual((root / "Data" / name).read_text(), self.SENTINEL)
        self.assertEqual(sorted(p.name for p in (root / "Data").iterdir()),
                         ["BuiltinLists.lua", "Tokens.lua"])

    def good_payload(self) -> dict[str, Any]:
        return {"catalog": CatalogTest().current(), "tokens": [{"tokenItemId": 1, "rewardItemIds": [2]}],
                "lists": [make_list()]}

    def test_second_temp_write_failure_leaves_originals(self) -> None:
        real = sync_builtin.write_temp
        calls: list[int] = []

        def flaky(path: Path, text: str) -> Path:
            calls.append(1)
            if len(calls) == 2:
                raise OSError("disk full")
            return real(path, text)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Catalog.lua").write_text((REPO_DIR / "Catalog.lua").read_text())
            (root / "Data").mkdir()
            for name in ("BuiltinLists.lua", "Tokens.lua"):
                (root / "Data" / name).write_text(self.SENTINEL)
            stderr = io.StringIO()
            with mock.patch.object(sync_builtin, "fetch_builtin", return_value=self.good_payload()), \
                    mock.patch.object(sync_builtin, "REPO_DIR", root), \
                    mock.patch.object(sync_builtin, "write_temp", side_effect=flaky), \
                    redirect_stderr(stderr), mock.patch("sys.argv", ["sync-builtin.py"]):
                code = sync_builtin.main()
            self.assertEqual(code, 1)
            self.assertIn("Error: disk full", stderr.getvalue())
            self.assert_untouched(root)

    def test_token_missing_rewards_fails_cleanly(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Catalog.lua").write_text((REPO_DIR / "Catalog.lua").read_text())
            (root / "Data").mkdir()
            for name in ("BuiltinLists.lua", "Tokens.lua"):
                (root / "Data" / name).write_text(self.SENTINEL)
            payload = self.good_payload()
            payload["tokens"] = [{"tokenItemId": 1}]
            stderr = io.StringIO()
            with mock.patch.object(sync_builtin, "fetch_builtin", return_value=payload), \
                    mock.patch.object(sync_builtin, "REPO_DIR", root), \
                    redirect_stderr(stderr), mock.patch("sys.argv", ["sync-builtin.py"]):
                code = sync_builtin.main()
            self.assertEqual(code, 1)
            self.assertTrue(stderr.getvalue().startswith("Error:"))
            self.assert_untouched(root)

    def test_main_writes_nothing_on_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Data").mkdir()
            sentinel = "-- untouched\n"
            (root / "Data" / "BuiltinLists.lua").write_text(sentinel)
            (root / "Data" / "Tokens.lua").write_text(sentinel)
            stderr = io.StringIO()
            with mock.patch.object(sync_builtin, "fetch_builtin", side_effect=sync_builtin.SyncError("boom")), \
                    mock.patch.object(sync_builtin, "REPO_DIR", root), redirect_stderr(stderr), \
                    mock.patch("sys.argv", ["sync-builtin.py"]):
                code = sync_builtin.main()
            self.assertEqual(code, 1)
            self.assertIn("Error: boom", stderr.getvalue())
            self.assertEqual((root / "Data" / "BuiltinLists.lua").read_text(), sentinel)
            self.assertEqual((root / "Data" / "Tokens.lua").read_text(), sentinel)


class DefaultSiteTest(unittest.TestCase):
    def test_default_site_is_bislist_io(self) -> None:
        self.assertEqual(sync_builtin.DEFAULT_SITE, "https://bislist.io")



class FetchTest(unittest.TestCase):
    def test_names_itself_because_the_site_refuses_generic_python_clients(self):
        response = mock.MagicMock()
        response.__enter__.return_value = io.BytesIO(b'{"lists": []}')
        with mock.patch.object(sync_builtin.urllib.request, "urlopen", return_value=response) as urlopen:
            self.assertEqual(sync_builtin.fetch_builtin("https://bislist.test/"), {"lists": []})
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "https://bislist.test/api/addon/builtin")
        self.assertEqual(request.get_header("User-agent"), sync_builtin.USER_AGENT)
        self.assertTrue(sync_builtin.USER_AGENT.startswith("BISListTooltip-sync/"))

if __name__ == "__main__":
    unittest.main()
