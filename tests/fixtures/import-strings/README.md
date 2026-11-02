# Import string format (BLT1)

Test vectors for the BIS List Tooltip import string. Each `<name>.txt` is an import string (plus a trailing newline); each `<name>.json` is the payload it must decode to. Regenerate with `node scripts/write-fixtures.ts`. A conforming decoder turns every `.txt` into a payload equal to its `.json`, skipping the number of entries given in the fixture table below.

## Envelope

```
BLT1:<base64>
```

- Prefix is the literal `BLT1:`.
- `<base64>` is the standard alphabet (`A-Z a-z 0-9 + /`), `=` padded, no line breaks. Encoders always pad. Decoders must accept padded input; accepting unpadded input is optional.
- The decoded bytes are a raw DEFLATE stream (RFC 1951, no zlib or gzip header or checksum) of the UTF-8 body.

## Decoding input

Strip ALL occurrences of exactly these four characters (space, tab, CR, LF) from the whole input before anything else; chat pastes add line breaks. Other characters (for example NBSP U+00A0) are not stripped and cause an error. Then check the prefix: if the input does not match `BLT<digits>:` the error is `prefix`; otherwise, if the characters between `BLT` and `:` are not exactly `1`, the error is `version` (so `BLT01:` and `BLT2:` are `version`).

## Body

UTF-8 text, lines joined by `\n`, no trailing newline, fields separated by a single tab (`\t`). Text fields never contain tab, CR or LF. The first line is the only `H` line; every following line is an `E` line.

```
H<TAB>listId<TAB>version<TAB>publishedAt<TAB>game<TAB>title<TAB>author
E<TAB>classToken<TAB>build<TAB>itemId<TAB>slotGroup<TAB>rank<TAB>label
```

| Field | Rule |
| --- | --- |
| listId | opaque string |
| version | integer >= 1. The site writes a CalVer integer, `YYYYMMDD * 1000 + N` (UTC publish date, N = 1..999 counting that day's publishes); see Versions below |
| publishedAt | integer >= 0, unix seconds |
| game | must be `forever` |
| title, author | free text |
| classToken | one of the 9 class tokens listed below; any other token: the line is skipped (see Unknown classes and slot groups) |
| build | free text, 1 to 32 characters (Unicode code points, not UTF-16 units or bytes), no tab, CR or LF; empty, longer, or containing CR is a `format` error, checked even on lines that are skipped |
| itemId | integer >= 1 |
| slotGroup | one of the 16 slot group ids listed below; any other id: the line is skipped (see Unknown classes and slot groups) |
| rank | integer >= 1 (1 = best) |
| label | free text |

Integers are decimal digits only (no sign, no decimal point, no leading or trailing spaces). An `H` line has exactly 7 fields and an `E` line exactly 7. A list with zero entries is valid.

## Unknown classes and slot groups

Classes and slot groups can be added to the site later. A decoder that meets an `E` line whose `classToken` or `slotGroup` it does not know skips that line instead of failing, and reports how many lines it skipped so the user can be told the import is partial. The skipped line must still be well formed: it has exactly 7 fields, its `build` is 1 to 32 characters, and its `itemId` and `rank` are valid integers, otherwise the error is `format`. Nothing else is lenient: an unknown `game`, line type, field count or bad integer is still an error.

## Build names

A build is free text under a class; a list can have any builds, not all of them. The site trims a name, collapses internal whitespace runs to one space and treats names as the same build when they match case-insensitively within a class ("Feral tank" and "Feral Tank"); the first spelling is the one written. Decoders do no such folding: they keep every name exactly as written, so `Fire` and `fire` in one class decode as two different build strings.

## Versions

`version` is an integer so numeric comparison keeps working: `YYYYMMDD * 1000 + N`, where the date is the UTC publish date and N counts that day's publishes from 1 to 999. `20261104001` is the first publish on 2026-11-04. For display, format it as `YYYY.MM.DD.N` with month and day zero-padded to 2 digits and N unpadded (`20261104001` is `2026.11.04.1`), and prefix `v` in UI text ("v2026.11.04.1"). A value is valid CalVer only if N is 1 to 999, the year is 1000 to 9999, the month is 1 to 12 and the day is a real calendar day of that month (leap years included). Any other integer displays as its plain decimal. Examples:

| Integer | Display |
| --- | --- |
| 20261104001 | 2026.11.04.1 |
| 20261231012 | 2026.12.31.12 |
| 20240229001 | 2024.02.29.1 |
| 5 | 5 |
| 20261304001 (month 13) | 20261304001 |
| 20260231001 (no Feb 31) | 20260231001 |
| 20261104000 (N = 0) | 20261104000 |
| 202611041000 (N = 1000) | 202611041000 |

Versions exceed 32 bits, so never format one with a 32-bit integer conversion (Lua `%d` on a 32-bit `long`).

## Entry order

Entries are written by class (order of the list below), then in the list's build order (builds with no entries are omitted), then slot group order, then rank ascending. Decoders recover the build order from the order builds first appear in the body, so a consumer showing builds should keep body order.

Class tokens, in order:

```
DRUID HUNTER MAGE PALADIN PRIEST ROGUE SHAMAN WARLOCK WARRIOR
```

Slot group ids, in order:

```
head neck shoulder back chest wrist hands waist legs feet finger trinket
weapon main-hand off-hand two-hand ranged relic
```

`weapon` holds Main Hand, One Hand and Two Hand items, ranked together; `main-hand` holds Main Hand and One Hand items; `two-hand` holds Two Hand items; `off-hand` holds Off Hand and One Hand items. A build uses either `weapon` or `main-hand` and `two-hand`, never both; the site rejects a draft that mixes them. The same one-handed item can be listed under `main-hand` (or `weapon`) and `off-hand` in one build.

A decoder must not depend on this order and returns entries in body order.

## Worked example

Decoded body of `basic.txt`, with each tab shown as `→` (the real body uses the tab character, not `→`):

```
H→fixtureBasic0001→20251030001→1761782400→forever→Basic Fixture→Fixture Author
E→MAGE→Fire→19019→head→1→Best
E→MAGE→Fire→19020→head→2→Pre-BIS
E→MAGE→Fire→19021→neck→1→Best
E→ROGUE→Rogue→19022→weapon→1→Melee Best
```

## Errors

| Code | Meaning |
| --- | --- |
| `prefix` | Does not start with `BLT<digits>:` (after whitespace stripping) |
| `version` | Starts with `BLT<digits>:` but the digits are not exactly `1` |
| `base64` | Payload is not valid base64 |
| `inflate` | Bytes are not a complete valid raw DEFLATE stream (e.g. truncated) |
| `format` | Body is not valid UTF-8, or violates the grammar above (wrong field count, bad integer, unknown game, missing, misplaced or duplicate `H` line, empty line, unknown line type, empty or over-long build). An unknown class or slot group is not an error; that line is skipped. |

## Fixtures

| Name | Content | Skipped entries |
| --- | --- | --- |
| basic | 4 entries, ASCII: Mage "Fire" head x2 and neck, Rogue "Rogue" weapon; version 20251030001 | 0 |
| unicode | accented, CJK and symbol characters in title, author and labels; Priest build `Ombre ★`; version 20251030003 | 0 |
| large | 36 builds (9 classes x their suggested builds) x 18 slot groups x 3 items = 1944 entries; version 20251030012 | 0 |
| unknown-class | 3 `E` lines, one for the unknown class `EVOKER`; the `.json` holds the other 2; version 20251030002 | 1 |
