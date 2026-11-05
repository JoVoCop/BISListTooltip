local wow = require("wow")
local helpers = require("helpers")

local function listString(id, version, title)
  local header = table.concat({ "H", id, tostring(version), "1761782400", "forever", title, "Author" }, "\t")
  return helpers.encode(header)
end

local function loadAddon(overrides)
  local ns, stubs = wow.load(overrides)
  ns.BuiltinLists = {}
  stubs.fire("ADDON_LOADED", ns.ADDON_NAME)
  return ns, stubs
end

local function rowFrames(stubs)
  local rows = {}
  for _, frame in ipairs(stubs.frames) do
    if rawget(frame, "title") and rawget(frame, "remove") then rows[#rows + 1] = frame end
  end
  return rows
end

local function visibleRows(stubs)
  local visible = {}
  for _, row in ipairs(rowFrames(stubs)) do
    if row.shown then visible[#visible + 1] = row end
  end
  return visible
end

local function textFrame(stubs, text)
  for _, frame in ipairs(stubs.frames) do
    local call = frame.last.SetText
    if call and call[1] == text then return frame end
  end
end

return {
  ["Init registers one canvas category named BIS List Tooltip"] = function(t)
    local _, stubs = loadAddon()
    t.eq(#stubs.categories, 1)
    t.eq(stubs.categories[1].name, "BIS List Tooltip")
    t.eq(#stubs.registered, 1)
    t.ok(stubs.registered[1] == stubs.categories[1])
  end,

  ["Open passes the category id to Settings"] = function(t)
    local ns, stubs = loadAddon()
    ns.Options.Open()
    t.eq(stubs.opened, { "BIS List Tooltip" })
  end,

  ["missing Settings prints the unavailable message and doesn't error"] = function(t)
    local ns, stubs = loadAddon({ Settings = false })
    t.eq(stubs.printed[#stubs.printed], "BIS List Tooltip: options are unavailable on this client.")
    ns.Options.Open()
    ns.Options.Refresh()
  end,

  ["Import passes Lists' messages through and refreshes"] = function(t)
    local ns = loadAddon()
    local refreshed = 0
    local refresh = ns.Options.Refresh
    ns.Options.Refresh = function() refreshed = refreshed + 1; return refresh() end
    local ok, message = ns.Options.Import("")
    t.eq(ok, false)
    t.eq(message, ns.ImportString.ERROR_MESSAGES.empty)
    t.eq(refreshed, 1)
    ok, message = ns.Options.Import(listString("abc", 1, "Mage BIS"))
    t.eq(ok, true)
    t.eq(message, 'Imported "Mage BIS" (version 1). It is now your active list.')
    t.eq(refreshed, 2)
  end,

  ["ConfirmRemove shows the all-characters warning; accepting removes"] = function(t)
    local ns, stubs = loadAddon()
    ns.Options.Import(listString("abc", 1, "Mage|cffBIS"))
    ns.Options.ConfirmRemove("abc")
    local popup = stubs.popups[#stubs.popups]
    t.eq(popup.which, "BISLT_CONFIRM_REMOVE")
    t.eq(StaticPopupDialogs.BISLT_CONFIRM_REMOVE.text, 'Remove "%s"?\n\nThis removes it for all characters on this account.')
    t.eq(StaticPopupDialogs.BISLT_CONFIRM_REMOVE.button1, "Remove")
    t.eq(StaticPopupDialogs.BISLT_CONFIRM_REMOVE.button2, "Cancel")
    t.eq(popup.args[1], "Mage||cffBIS")
    t.ok(ns.Lists.Get("abc"), "still present before accepting")
    stubs.acceptPopup(popup)
    t.eq(ns.Lists.Get("abc"), nil)
  end,

  ["class checkboxes write displayClass"] = function(t)
    local ns = loadAddon()
    ns.Options.SetClassShown("WARRIOR", true)
    t.eq(BISListTooltipCharDB.displayClass.WARRIOR, true)
    ns.Options.SetClassShown("WARRIOR", false)
    t.eq(BISListTooltipCharDB.displayClass.WARRIOR, false)
  end,

  ["notice toggle writes noticesEnabled"] = function(t)
    local ns = loadAddon()
    ns.Options.SetNoticesEnabled(false)
    t.eq(BISListTooltipDB.noticesEnabled, false)
    ns.Options.SetNoticesEnabled(true)
    t.eq(BISListTooltipDB.noticesEnabled, true)
  end,

  ["blank line toggles write blankLineBefore and blankLineAfter"] = function(t)
    local ns = loadAddon()
    t.eq(BISListTooltipDB.blankLineBefore, true)
    t.eq(BISListTooltipDB.blankLineAfter, true)
    ns.Options.SetBlankLineBefore(false)
    ns.Options.SetBlankLineAfter(false)
    t.eq(BISListTooltipDB.blankLineBefore, false)
    t.eq(BISListTooltipDB.blankLineAfter, false)
    ns.Options.SetBlankLineBefore(true)
    ns.Options.SetBlankLineAfter(true)
    t.eq(BISListTooltipDB.blankLineBefore, true)
    t.eq(BISListTooltipDB.blankLineAfter, true)
  end,

  ["Refresh shows one row per list, Remove only on imported rows, and hides surplus rows"] = function(t)
    local ns, stubs = wow.load()
    ns.BuiltinLists = { { listId = "core", version = 2, publishedAt = 1761782400, title = "Core", author = "A", importString = listString("core", 2, "Core") } }
    stubs.fire("ADDON_LOADED", ns.ADDON_NAME)
    ns.Options.Import(listString("abc", 1, "Mage BIS"))
    local rows = visibleRows(stubs)
    t.eq(#rows, 2)
    local byId = {}
    for _, row in ipairs(rows) do byId[row.listId] = row end
    t.eq(byId.core.remove.shown, false)
    t.eq(byId.abc.remove.shown, true)
    t.eq(byId.core.meta.last.SetText[1], "v2 · 2025-10-30 · Built-in")
    t.eq(byId.abc.meta.last.SetText[1], "v1 · 2025-10-30 · Imported")

    ns.Lists.Remove("abc")
    t.eq(#visibleRows(stubs), 1)
    t.eq(#rowFrames(stubs), 2, "row frames are pooled, not discarded")

    ns.Options.Import(listString("cal", 20251030001, "Calendar"))
    local calRow
    for _, row in ipairs(visibleRows(stubs)) do if row.listId == "cal" then calRow = row end end
    t.eq(calRow.meta.last.SetText[1], "v2025.10.30.1 · 2025-10-30 · Imported")
  end,

  ["Import status is green on success and red on failure"] = function(t)
    local ns, stubs = loadAddon()
    local _, failure = ns.Options.Import("")
    local status = textFrame(stubs, failure)
    t.eq(status.last.SetTextColor, { 1, 0.3, 0.3 })
    local _, success = ns.Options.Import(listString("abc", 1, "Mage BIS"))
    t.eq(status.last.SetText[1], success)
    t.eq(status.last.SetTextColor, { 0.3, 1, 0.3 })
  end,

  ["a publish date that cannot be formatted shows unknown date"] = function(t)
    local ns, stubs = wow.load({ date = function() return nil end })
    ns.BuiltinLists = {}
    stubs.fire("ADDON_LOADED", ns.ADDON_NAME)
    ns.Options.Import(listString("abc", 1, "Mage BIS"))
    t.eq(visibleRows(stubs)[1].meta.last.SetText[1], "v1 · unknown date · Imported")
  end,

  ["removing the active list explains the fallback in the status line"] = function(t)
    local ns, stubs = loadAddon()
    ns.Options.Import(listString("abc", 1, "Mage BIS"))
    ns.Options.ConfirmRemove("abc")
    stubs.acceptPopup(stubs.popups[#stubs.popups])
    local status = textFrame(stubs, '"Mage BIS" was removed, so no list is active.')
    t.ok(status, "status line shows the fallback message")
    t.eq(status.last.SetTextColor, { 1, 0.82, 0 })
  end,
}
