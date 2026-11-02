local wow = require("wow")

local function record(id, version, source, title)
  return { listId = id, version = version, publishedAt = 1761782400, title = title or id, author = "A", importString = "x", source = source }
end

-- Notices is wired against the real Lists store but with hand-made records.
local function setup(held, db, overrides)
  local ns, stubs = wow.load(overrides)
  local lists = {}
  for _, rec in ipairs(held) do lists[rec.listId] = rec end
  ns.Lists.Get = function(id) return lists[id] end
  ns.Lists.HeldVersion = function(id) return lists[id] and lists[id].version or nil end
  BISListTooltipDB = db or { notified = {}, noticesEnabled = true }
  ns.Notices.Init()
  return ns, stubs, lists
end

return {
  ["popup text shows the CalVer version"] = function(t)
    local ns, stubs = setup({ record("abc", 20261031001, "imported", "Mage BIS") })
    ns.Notices.Offer("abc", 20261031002, 1761782400)
    t.ok(stubs.popups[1].args[1]:find("version 2026.10.31.2,", 1, true))
  end,

  ["shows the imported-list popup with title, version, date and URL"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported", "Mage BIS") })
    ns.Notices.Offer("abc", 5, 1761782400)
    t.eq(#stubs.popups, 1)
    local popup = stubs.popups[1]
    t.eq(popup.which, "BISLT_NEWER_IMPORTED")
    t.eq(popup.args[1], 'A newer version of "Mage BIS" is available: version 5, published 2025-10-30.\n\nCopy the link, open it in your browser and import the new version.')
    t.eq(popup.data.url, "https://bislist.io/lists/abc")
    t.eq(popup.data.listId, "abc")
    t.eq(popup.dialog.editBox.text, "https://bislist.io/lists/abc")
    t.eq(StaticPopupDialogs.BISLT_NEWER_IMPORTED.text, "%s")
    t.eq(StaticPopupDialogs.BISLT_NEWER_IMPORTED.hasEditBox, true)
    t.eq(StaticPopupDialogs.BISLT_NEWER_IMPORTED.timeout, 0)
  end,

  ["built-in list gets the CurseForge popup"] = function(t)
    local ns, stubs = setup({ record("core", 3, "builtin", "Core List") })
    ns.Notices.Offer("core", 4, 1761782400)
    t.eq(stubs.popups[1].which, "BISLT_NEWER_BUILTIN")
    t.eq(stubs.popups[1].args[1], 'A newer version of the built-in list "Core List" is out: version 4, published 2025-10-30.\n\nUpdate BIS List Tooltip through CurseForge to get it.')
  end,

  ["in combat waits; PLAYER_REGEN_ENABLED shows it"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported") })
    stubs.state.inCombat = true
    ns.Notices.Offer("abc", 5, 1761782400)
    t.eq(#stubs.popups, 0)
    stubs.state.inCombat = false
    stubs.fire("PLAYER_REGEN_ENABLED")
    t.eq(#stubs.popups, 1)
  end,

  ["in an instance waits; PLAYER_ENTERING_WORLD shows it"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported") })
    stubs.state.inInstance = true
    ns.Notices.Offer("abc", 5, 1761782400)
    t.eq(#stubs.popups, 0)
    stubs.state.inInstance = false
    stubs.fire("PLAYER_ENTERING_WORLD")
    t.eq(#stubs.popups, 1)
  end,

  ["ZONE_CHANGED_NEW_AREA also retries"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported") })
    stubs.state.inInstance = true
    ns.Notices.Offer("abc", 5, 1761782400)
    stubs.state.inInstance = false
    stubs.fire("ZONE_CHANGED_NEW_AREA")
    t.eq(#stubs.popups, 1)
  end,

  ["two newer lists show one at a time, the second after the first hides"] = function(t)
    local ns, stubs = setup({ record("b", 1, "imported", "Beta"), record("a", 1, "imported", "Alpha") })
    ns.Notices.Offer("b", 2, 1761782400)
    ns.Notices.Offer("a", 2, 1761782400)
    t.eq(#stubs.popups, 1)
    t.eq(stubs.popups[1].data.listId, "b")
    stubs.hidePopup(stubs.popups[1])
    t.eq(#stubs.popups, 1)
    stubs.advance(0)
    t.eq(#stubs.popups, 2)
    t.eq(stubs.popups[2].data.listId, "a")
  end,

  ["lowest title is shown first when several are pending"] = function(t)
    local ns, stubs = setup({ record("b", 1, "imported", "Beta"), record("a", 1, "imported", "Alpha") })
    stubs.state.inCombat = true
    ns.Notices.Offer("b", 2, 1761782400)
    ns.Notices.Offer("a", 2, 1761782400)
    stubs.state.inCombat = false
    stubs.fire("PLAYER_REGEN_ENABLED")
    t.eq(stubs.popups[1].data.listId, "a")
  end,

  ["the same version is never shown twice, even after a reload"] = function(t)
    local db = { notified = {}, noticesEnabled = true }
    local ns, stubs = setup({ record("abc", 3, "imported") }, db)
    ns.Notices.Offer("abc", 5, 1761782400)
    t.eq(db.notified.abc, 5)
    local ns2, stubs2 = setup({ record("abc", 3, "imported") }, db)
    ns2.Notices.Offer("abc", 5, 1761782400)
    t.eq(#stubs2.popups, 0)
    ns2.Notices.Offer("abc", 6, 1761782400)
    t.eq(#stubs2.popups, 1)
  end,

  ["a version imported before the popup could show is dropped"] = function(t)
    local ns, stubs, lists = setup({ record("abc", 3, "imported") })
    stubs.state.inCombat = true
    ns.Notices.Offer("abc", 5, 1761782400)
    lists.abc.version = 5
    stubs.state.inCombat = false
    stubs.fire("PLAYER_REGEN_ENABLED")
    t.eq(#stubs.popups, 0)
  end,

  ["disabled notices show nothing"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported") }, { notified = {}, noticesEnabled = false })
    ns.Notices.Offer("abc", 5, 1761782400)
    t.eq(#stubs.popups, 0)
  end,

  ["offers of v5 then v6 for the same list in one session show one popup"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported") })
    ns.Notices.Offer("abc", 5, 1761782400)
    stubs.hidePopup(stubs.popups[1])
    ns.Notices.Offer("abc", 6, 1761782400)
    t.eq(#stubs.popups, 1)
  end,

  ["a missing edit box method does not error"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported") })
    local definition = StaticPopupDialogs.BISLT_NEWER_IMPORTED
    definition.OnShow({}, { url = "u" })
    local text
    definition.OnShow({ EditBox = { SetText = function(_, value) text = value end } }, { url = "u" })
    t.eq(text, "u")
  end,

  ["pipes in a title are escaped"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported", "|cffff0000Bad") })
    ns.Notices.Offer("abc", 5, 1761782400)
    t.ok(stubs.popups[1].args[1]:find('"||cffff0000Bad"', 1, true))
  end,

  ["offers for lists not held are ignored"] = function(t)
    local ns, stubs = setup({})
    ns.Notices.Offer("ghost", 5, 1761782400)
    t.eq(#stubs.popups, 0)
  end,

  ["a date that cannot be formatted still shows the popup"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported", "Mage BIS") }, nil, { date = function() return nil end })
    ns.Notices.Offer("abc", 5, 1761782400)
    t.eq(#stubs.popups, 1)
    t.ok(stubs.popups[1].args[1]:find("published an unknown date.", 1, true))
  end,

  ["a message that cannot be built drops the offer instead of failing every retry"] = function(t)
    local ns, stubs = setup({ record("abc", 3, "imported", "Mage BIS") }, nil, { date = function() error("boom") end })
    t.ok(pcall(ns.Notices.Offer, "abc", 5, 1761782400))
    t.eq(#stubs.popups, 0)
    _G.date = os.date
    stubs.fire("PLAYER_REGEN_ENABLED")
    t.eq(#stubs.popups, 0)
  end,

  ["a record without a title uses its id in the text and the sort"] = function(t)
    local untitled = record("abc", 3, "imported")
    untitled.title = nil
    local ns, stubs = setup({ untitled, record("b", 3, "imported", "bravo") })
    stubs.state.inCombat = true
    ns.Notices.Offer("abc", 5, 1761782400)
    ns.Notices.Offer("b", 5, 1761782400)
    stubs.state.inCombat = false
    stubs.fire("PLAYER_REGEN_ENABLED")
    t.eq(#stubs.popups, 1)
    t.eq(stubs.popups[1].data.listId, "abc")
    t.ok(stubs.popups[1].args[1]:find('"abc"', 1, true))
  end,
}
