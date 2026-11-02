# BIS List Tooltip

A World of Warcraft addon for WoW Forever that adds best-in-slot information to item tooltips, from the list you choose.

Hover an item and, if it is on your active list, the tooltip shows which builds want it, with the list author's label and rank (for example "Best - 1/2"). Off Hand entries are tagged "(Off Hand)". Hovering a token shows the lines of the items it can be turned into.

## Importing a list

1. Open the list on [bislist.io](https://bislist.io) and copy its import string.
2. In game, type `/blt` to open the options panel.
3. Paste the string into the import box and press Import.

Built-in lists ship with each release, once the owner has synced them with `tools/sync-builtin.py` before tagging. Imported lists are shared across your account; the active list is chosen per character. Importing a list your account did not have makes it the active list on that character.

## Options

* Active list: which list the tooltip uses, per character.
* Class filter: which classes' lines are shown, per character. Defaults to the character's own class.
* Remove an imported list from the list overview.
* Guild update notices (on by default).

## Guild update notices

If a guildmate also runs the addon and holds a newer version of a list you have, you get one popup. For an imported list it offers the list's web address; for a built-in list it tells you to update the addon through CurseForge. Popups appear once per list version, at most one per list per session, never in combat or an instance.

## Development

* Lua tests (needs `lua5.1`): `lua5.1 tests/run.lua`
* Python tests: `python3 -m unittest discover -s tools -p 'test_*.py' -v`
* Copy the addon into your game: `tools/install-addon.sh "<path to Interface/AddOns>"`

Only the Python 3 standard library is used by the tools.

### Syncing built-in lists

1. `python3 tools/sync-builtin.py` (optionally `--site URL`). It rewrites `Data/BuiltinLists.lua` and `Data/Tokens.lua` and prints what was added, removed or updated.
2. Review the diff and run the tests.
3. Add `changelogs/vX.Y.Z.md`.
4. Tag `vX.Y.Z` and push the tag. The release workflow builds the zip, creates the GitHub release and uploads the zip to CurseForge with the changelog; a missing changelog fails it. A tag with `-beta` or `-alpha` in it is published to CurseForge as a beta or alpha.

### CurseForge publishing

The release workflow uploads with `tools/publish-curseforge.py`, which needs:

* the repository secret `CURSEFORGE_API_TOKEN`, an API token from the CurseForge account settings (without it the upload is skipped with a notice);
* the repository variable `CURSEFORGE_PROJECT_ID`, the project's numeric id from its CurseForge page;
* the repository variable `CURSEFORGE_GAME_VERSIONS`, the CurseForge game version id(s) the file supports, comma separated. List them with `CURSEFORGE_API_TOKEN=... tools/publish-curseforge.py --list-game-versions Forever`.
