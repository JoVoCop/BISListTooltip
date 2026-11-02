# In-game checks

## Part 1: Spike (run first, any Forever client)

Each snippet says what result means OK and what the addon does otherwise.

1. `/dump TooltipDataProcessor ~= nil, Enum.TooltipDataType and Enum.TooltipDataType.Item`
   - OK: `true, 0`.
   - Otherwise: the tooltip hook is skipped and no BIS lines appear; the addon must not error.

2. `/run TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(t, d) t:AddLine("BLT " .. tostring(d and d.id)) end)`
   - Hover a bag item, a chat item link, a comparison tooltip and a loot-roll item. Repeat in combat and inside a dungeon.
   - OK: each shows `BLT <itemId>`.
   - Otherwise: the hook does not fire for that tooltip kind; record which, and BIS lines will be missing there.

3. `/dump issecretvalue ~= nil`
   - Record the result. In combat, check whether the snippet from 2 still shows a number.
   - OK: either `issecretvalue` is nil (nothing is hidden), or the item id is still readable in combat.
   - Otherwise: the item id is hidden in combat; the addon skips the lookup there instead of erroring.

4. `/dump C_Texture.GetAtlasInfo("classicon-druid") ~= nil`
   - OK: `true` (class icons work in tooltip lines).
   - Otherwise: the addon drops the icon and shows the build name only.

5. `/dump Settings.RegisterCanvasLayoutCategory ~= nil, Settings.OpenToCategory ~= nil`
   - OK: `true, true`.
   - Otherwise: the options panel is not registered; `/blt` prints a message instead of opening it.

6. Two guildmates run this on both clients:
   `/run C_ChatInfo.RegisterAddonMessagePrefix("BISLT"); local f = CreateFrame("Frame"); f:RegisterEvent("CHAT_MSG_ADDON"); f:SetScript("OnEvent", function(_, _, p, m, c, s) if p == "BISLT" then print(p, m, c, s) end end)`
   - Then on one client: `/dump C_ChatInfo.SendAddonMessage("BISLT", "ping", "GUILD")`, outside, in combat and inside a dungeon.
   - Record the result codes, whether the other client received it, and the sender format (`Name-Realm`?).
   - OK: the message arrives with result code 0 in every situation.
   - Otherwise: newer-version notices only work in the situations where delivery succeeds; the addon never errors on a failed send.

7. After the addon is installed, run `/blt`.
   - OK: the addon's options panel opens (checks the `Settings.OpenToCategory` signature).
   - Otherwise: the panel does not open; record the client's `Settings.OpenToCategory` signature.

## Part 2: Acceptance (installed addon)

Use `tools/install-addon.sh` or a release zip. Have a real import string copied from bislist.io, and two characters (A and B) on the same account.

1. Install the addon and log in.
   - Expected: no Lua errors; the addon appears in the AddOns list as "BIS List Tooltip".
2. Type `/blt`.
   - Expected: the options panel opens.
3. Paste the real import string into the import box and press Import.
   - Expected: a success message; the list appears in the list overview with its version (like v2026.11.04.1), date and "Imported"; it is the active list.
4. Hover an item on the list in a bag, a chat item link, a comparison tooltip and a loot roll.
   - Expected: each tooltip shows a blank line, a header in green with the list's title, then lines `<class icon> <build name>` and `<label> - <rank>/<total>`. Off Hand entries carry "(Off Hand)".
5. Use a list with one build that ranks weapons together in Weapon and one that ranks them as Main Hand and Two Hand (on bislist.io, the Classic Phase 4 list has both: Feral DPS uses Weapon, Fury uses Main Hand and Two Hand). Hover a weapon from each, and a one-hander listed in both Main Hand and Off Hand.
   - Expected: Weapon, Main Hand and Two Hand lines read `<build name>` with no slot added; only Off Hand lines carry "(Off Hand)"; the one-hander shows both its Main Hand and its Off Hand line, each with its own rank.
6. Hover an item that is not on the list.
   - Expected: nothing is added.
7. Hover a token that has rewards on the list.
   - Expected: the rewards' lines appear.
8. In the options, untick a class that appears in the lines, then hover again.
   - Expected: that class's lines disappear; other classes remain.
9. On character A, switch the active list to a different list. Log in character B.
   - Expected: B still has its own active list, unchanged.
10. On A, make the imported list active, then remove it (confirm the popup). Log in B, which had it active.
    - Expected on B: one chat message saying the list was removed and which list is now used; hovering items causes no errors.
    - Expected on A, right after confirming the removal: the options status line says the list was removed and which list is now used, and tooltips use that list at once.
11. Type `/reload`.
    - Expected: lists, active list and class filter are unchanged.
12. Two guildmates each hold the same list at different versions. The one with the older version logs in or reloads while out of combat and outside an instance.
    - Expected: the older one gets exactly one popup about the newer version; no popup while in combat or in a dungeon (it appears after leaving); no second popup after `/reload`.
