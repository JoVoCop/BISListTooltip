import importlib.util
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("generate_changelog", TOOLS_DIR / "generate-curseforge-changelog.py")
assert spec is not None and spec.loader is not None
generate_changelog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generate_changelog)


def write_changelogs(directory: Path, versions: list[str]) -> None:
    for version in versions:
        (directory / f"{version}.md").write_text(f"notes {version}", encoding="utf-8")


class CombineTest(unittest.TestCase):
    def test_versions_sort_numerically_not_alphabetically(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            write_changelogs(directory, ["v1.9.0", "v1.10.0", "v2.0.0"])
            names = [path.name for path in generate_changelog.newest_changelogs(directory)]
            self.assertEqual(names, ["v2.0.0.md", "v1.10.0.md", "v1.9.0.md"])

    def test_keeps_only_the_newest_four(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            write_changelogs(directory, ["v1.0.0", "v1.1.0", "v1.2.0", "v1.10.0", "v2.0.0"])
            text = generate_changelog.combine(directory)
            self.assertEqual(text.count("---"), 3)
            self.assertNotIn("v1.0.0", text)
            self.assertTrue(text.startswith("notes v2.0.0"))

    def test_fewer_than_four_files_have_no_trailing_separator(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            write_changelogs(directory, ["v2.0.0", "v2.0.1"])
            self.assertEqual(generate_changelog.combine(directory), "notes v2.0.1\n\n---\n\nnotes v2.0.0")

    def test_single_file_has_no_separator(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            write_changelogs(directory, ["v2.0.0"])
            self.assertEqual(generate_changelog.combine(directory), "notes v2.0.0")

    def test_ignores_files_that_are_not_version_changelogs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            write_changelogs(directory, ["v2.0.0"])
            (directory / "README.md").write_text("not a changelog", encoding="utf-8")
            self.assertEqual(generate_changelog.combine(directory), "notes v2.0.0")


if __name__ == "__main__":
    unittest.main()
