local wow = require("wow")

local function loadAddon(overrides)
  local ns, stubs = wow.load(overrides)
  stubs.fire("ADDON_LOADED", ns.ADDON_NAME)
  return ns, stubs
end

local ALL_TOKENS = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

return {
  ["first load shows every class"] = function(t)
    loadAddon({})
    for _, token in ipairs(ALL_TOKENS) do t.eq(BISListTooltipCharDB.displayClass[token], true) end
    t.eq(BISListTooltipDB, { schema = 1, lists = {}, notified = {}, noticesEnabled = true, blankLineBefore = true, blankLineAfter = true })
  end,

  ["existing settings survive a reload"] = function(t)
    loadAddon({
      BISListTooltipDB = { schema = 1, lists = { a = { listId = "a", version = 1 } }, notified = { a = 2 }, noticesEnabled = false },
      BISListTooltipCharDB = { displayClass = { MAGE = false, WARRIOR = true }, activeListId = "a" },
    })
    t.eq(BISListTooltipDB.noticesEnabled, false)
    t.eq(BISListTooltipDB.notified, { a = 2 })
    t.eq(BISListTooltipDB.lists.a.listId, "a")
    t.eq(BISListTooltipCharDB.displayClass, { MAGE = false, WARRIOR = true })
    t.eq(BISListTooltipCharDB.activeListId, "a")
  end,

  ["corrupt saved variables are replaced"] = function(t)
    loadAddon({ BISListTooltipDB = "x", BISListTooltipCharDB = 5 })
    t.eq(BISListTooltipDB, { schema = 1, lists = {}, notified = {}, noticesEnabled = true, blankLineBefore = true, blankLineAfter = true })
    t.eq(BISListTooltipCharDB.displayClass.MAGE, true)
    t.eq(BISListTooltipCharDB.displayClass.ROGUE, true)
  end,

  ["corrupt nested saved variables are replaced"] = function(t)
    loadAddon({
      BISListTooltipDB = { schema = 1, lists = "x", notified = 3, noticesEnabled = false },
      BISListTooltipCharDB = { displayClass = 5 },
    })
    t.eq(BISListTooltipDB, { schema = 1, lists = {}, notified = {}, noticesEnabled = false, blankLineBefore = true, blankLineAfter = true })
    t.eq(BISListTooltipCharDB.displayClass.MAGE, true)
    t.eq(BISListTooltipCharDB.displayClass.ROGUE, true)
  end,

  ["ADDON_LOADED for another addon does nothing"] = function(t)
    local ns, stubs = wow.load()
    stubs.fire("ADDON_LOADED", "SomethingElse")
    t.eq(BISListTooltipDB, nil)
    t.eq(BISListTooltipCharDB, nil)
    t.eq(#stubs.tooltipCallbacks, 0)
    t.eq(stubs.printed, {})
  end,

  ["loading installs the tooltip hook"] = function(t)
    local _, stubs = loadAddon()
    t.eq(#stubs.tooltipCallbacks, 1)
  end,

  ["login prints the fallback message"] = function(t)
    local ns, stubs = loadAddon({ BISListTooltipCharDB = { displayClass = {}, activeListId = "gone", activeListTitle = "Old" } })
    ns.BuiltinLists = {}
    stubs.fire("PLAYER_LOGIN")
    t.eq(stubs.printed, { 'BIS List Tooltip: "Old" was removed, so no list is active.' })
  end,

  ["login before the addon loaded does not error"] = function(t)
    local _, stubs = wow.load()
    stubs.fire("PLAYER_LOGIN")
    t.eq(stubs.printed, {})
  end,

  ["missing Enum item type prints the disabled message"] = function(t)
    local _, stubs = loadAddon({ Enum = {} })
    t.eq(stubs.printed, { "BIS List Tooltip: this game client has no item tooltip hook, so tooltips are disabled." })
  end,

  ["missing TooltipDataProcessor prints the disabled message and doesn't error"] = function(t)
    local _, stubs = loadAddon({ TooltipDataProcessor = false })
    t.eq(stubs.printed, { "BIS List Tooltip: this game client has no item tooltip hook, so tooltips are disabled." })
  end,

  ["/blt opens the options when they exist and is silent otherwise"] = function(t)
    local ns = loadAddon()
    t.eq(SLASH_BISLISTTOOLTIP1, "/blt")
    SlashCmdList.BISLISTTOOLTIP()
    local opened = 0
    ns.Options = { Open = function() opened = opened + 1 end }
    SlashCmdList.BISLISTTOOLTIP()
    t.eq(opened, 1)
  end,

  ["a throwing Options.Init does not stop tooltips, other modules or the login fallback"] = function(t)
    local ns, stubs = wow.load({ BISListTooltipCharDB = { displayClass = {}, activeListId = "gone", activeListTitle = "Old" } })
    ns.BuiltinLists = {}
    local reported = {}
    _G.geterrorhandler = function() return function(message) reported[#reported + 1] = message end end
    ns.Options.Init = function() error("boom") end
    stubs.fire("ADDON_LOADED", ns.ADDON_NAME)
    t.eq(#stubs.tooltipCallbacks, 1)
    t.eq(#reported, 1)
    t.ok(reported[1]:find("boom", 1, true))
    stubs.fire("PLAYER_LOGIN")
    t.eq(stubs.printed, { 'BIS List Tooltip: "Old" was removed, so no list is active.' })
  end,

  ["a throwing Comms.Init does not stop Notices and Options from initialising"] = function(t)
    local ns, stubs = wow.load()
    ns.BuiltinLists = {}
    local initialised = {}
    ns.Comms.Init = function() error("boom") end
    ns.Notices.Init = function() initialised[#initialised + 1] = "notices" end
    ns.Options.Init = function() initialised[#initialised + 1] = "options" end
    stubs.fire("ADDON_LOADED", ns.ADDON_NAME)
    t.eq(initialised, { "notices", "options" })
    t.ok(stubs.printed[1]:find("boom", 1, true), "reported through print without geterrorhandler")
  end,
}
