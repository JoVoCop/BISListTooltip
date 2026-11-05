local wow = require("wow")

local ALL_SHOWN = {}

local function entry(classToken, build, label, rank, total, slotGroup, buildPosition)
  return { classToken = classToken, build = build, label = label, rank = rank, total = total, slotGroup = slotGroup or "head", buildPosition = buildPosition or 1 }
end

local function fakeTooltip()
  local tooltip = { calls = {} }
  function tooltip:AddLine(text) self.calls[#self.calls + 1] = { "line", text } end
  function tooltip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    self.calls[#self.calls + 1] = { "double", left, right, lr, lg, lb, rr, rg, rb }
  end
  return tooltip
end

local function withActiveList(ns, index, title)
  ns.Lists.GetActive = function() return title and { listId = "x", version = 1, title = title } or nil end
  ns.Lists.GetActiveIndex = function() return title and index or nil end
end

local INDEX = {
  [100] = { entry("MAGE", "Arcane", "Best", 1, 3), entry("WARRIOR", "Fury", "Alt", 2, 4) },
  [200] = { entry("MAGE", "Fire", "Pre-raid", 1, 2, "head", 2) },
  [300] = { entry("MAGE", "Fire", "Pre-raid", 1, 2, "head", 2), entry("MAGE", "Arcane", "Best", 1, 3) },
}

return {
  ["lines for an item with two builds, class colour and n/m"] = function(t)
    local ns = wow.load()
    local lines = ns.Tooltip.BuildLines(100, INDEX, {}, ALL_SHOWN)
    local mage, warrior = RAID_CLASS_COLORS.MAGE, RAID_CLASS_COLORS.WARRIOR
    t.eq(lines, {
      { left = "|A:classicon-mage|a Arcane", right = "Best - 1/3", r = mage.r, g = mage.g, b = mage.b },
      { left = "|A:classicon-warrior|a Fury", right = "Alt - 2/4", r = warrior.r, g = warrior.g, b = warrior.b },
    })
  end,

  ["token shows its rewards' lines without duplicates"] = function(t)
    local ns = wow.load()
    local rewards = { [900] = { 200, 300 } }
    local lines = ns.Tooltip.BuildLines(900, INDEX, rewards, ALL_SHOWN)
    local texts = {}
    for _, line in ipairs(lines) do texts[#texts + 1] = line.left:gsub("^|A:[^|]*|a ", "") .. " " .. line.right end
    t.eq(texts, { "Arcane Best - 1/3", "Fire Pre-raid - 1/2" })
  end,

  ["the same build on two slot groups keeps both lines"] = function(t)
    local ns = wow.load()
    local index = { [1] = { entry("ROGUE", "Combat", "Best", 1, 1, "weapon"), entry("ROGUE", "Combat", "Best", 1, 1, "off-hand") } }
    local lines = ns.Tooltip.BuildLines(1, index, {}, ALL_SHOWN)
    t.eq(#lines, 2)
    local reversed = { [1] = { index[1][2], index[1][1] } }
    local reorderedLines = ns.Tooltip.BuildLines(1, reversed, {}, ALL_SHOWN)
    t.eq({ reorderedLines[1].left, reorderedLines[2].left }, { lines[1].left, lines[2].left })
    t.eq({ (lines[1].left:gsub("^|A:[^|]*|a ", "")), (lines[2].left:gsub("^|A:[^|]*|a ", "")) }, { "Combat", "Combat (Off Hand)" })
  end,

  ["only Off Hand names its slot; Main Hand and Two Hand read like Weapon"] = function(t)
    local ns = wow.load()
    local index = { [1] = { entry("WARRIOR", "Fury", "Best", 1, 2, "main-hand"), entry("WARRIOR", "Fury", "Best", 1, 1, "off-hand") },
                    [2] = { entry("WARRIOR", "Fury", "Best", 1, 1, "two-hand") } }
    local strip = function(line) return (line.left:gsub("^|A:[^|]*|a ", "")) end
    local oneHander = ns.Tooltip.BuildLines(1, index, {}, ALL_SHOWN)
    t.eq({ strip(oneHander[1]), strip(oneHander[2]) }, { "Fury", "Fury (Off Hand)" })
    t.eq(strip(ns.Tooltip.BuildLines(2, index, {}, ALL_SHOWN)[1]), "Fury")
  end,

  ["token rewards merge in the list's build order, not reward order"] = function(t)
    local ns = wow.load()
    local index = {
      [10] = { entry("MAGE", "Fire", "Best", 1, 1, "head", 2) },
      [20] = { entry("MAGE", "Arcane", "Best", 1, 1, "head", 1) },
    }
    local lines = ns.Tooltip.BuildLines(900, index, { [900] = { 10, 20 } }, ALL_SHOWN)
    local builds = {}
    for _, line in ipairs(lines) do builds[#builds + 1] = (line.left:gsub("^|A:[^|]*|a ", "")) end
    t.eq(builds, { "Arcane", "Fire" })
  end,

  ["author text is escaped in build, label and list title"] = function(t)
    local ns = wow.load()
    local index = { [5] = { entry("MAGE", "|cffff0000Evil|r", "A|B", 1, 1) } }
    withActiveList(ns, index, "T|cffff0000x")
    local tooltip = fakeTooltip()
    ns.Tooltip.Decorate(tooltip, 5)
    t.eq(tooltip.calls[2][2], "|cff0af5a2T||cffff0000x|r")
    t.ok(tooltip.calls[3][2]:find("||cffff0000Evil||r", 1, true))
    t.eq(tooltip.calls[3][3], "A||B - 1/1")
  end,

  ["hidden class is dropped"] = function(t)
    local ns = wow.load()
    local lines = ns.Tooltip.BuildLines(100, INDEX, {}, { MAGE = false })
    t.eq(#lines, 1)
    t.eq(lines[1].right, "Alt - 2/4")
  end,

  ["no CreateAtlasMarkup gives the plain build name"] = function(t)
    local ns = wow.load({ CreateAtlasMarkup = false })
    t.eq(ns.Tooltip.BuildLines(200, INDEX, {}, ALL_SHOWN)[1].left, "Fire")
  end,

  ["missing class colour falls back to white"] = function(t)
    local ns = wow.load({ RAID_CLASS_COLORS = {} })
    local line = ns.Tooltip.BuildLines(200, INDEX, {}, ALL_SHOWN)[1]
    t.eq({ line.r, line.g, line.b }, { 1, 1, 1 })
  end,

  ["Decorate adds blank line, header with list title, lines, then blank line"] = function(t)
    local ns = wow.load()
    withActiveList(ns, INDEX, "My List")
    local tooltip = fakeTooltip()
    ns.Tooltip.Decorate(tooltip, 200)
    local color = RAID_CLASS_COLORS.MAGE
    t.eq(tooltip.calls, {
      { "line", " " },
      { "line", "|cff0af5a2My List|r" },
      { "double", "|A:classicon-mage|a Fire", "Pre-raid - 1/2", color.r, color.g, color.b, color.r, color.g, color.b },
      { "line", " " },
    })
  end,

  ["Decorate leaves out the blank lines that are turned off"] = function(t)
    local ns = wow.load()
    withActiveList(ns, INDEX, "My List")
    local function kinds(db)
      BISListTooltipDB = db
      local tooltip = fakeTooltip()
      ns.Tooltip.Decorate(tooltip, 200)
      local texts = {}
      for _, call in ipairs(tooltip.calls) do texts[#texts + 1] = call[1] == "line" and call[2] or "entry" end
      return texts
    end
    local header = "|cff0af5a2My List|r"
    t.eq(kinds({ blankLineBefore = false, blankLineAfter = true }), { header, "entry", " " })
    t.eq(kinds({ blankLineBefore = true, blankLineAfter = false }), { " ", header, "entry" })
    t.eq(kinds({ blankLineBefore = false, blankLineAfter = false }), { header, "entry" })
    t.eq(kinds({}), { " ", header, "entry", " " })
  end,

  ["Decorate does nothing for an unknown item, no active list, nil id, string id, or secret id"] = function(t)
    local ns, stubs = wow.load()
    withActiveList(ns, INDEX, "My List")
    local tooltip = fakeTooltip()
    ns.Tooltip.Decorate(tooltip, 999)
    ns.Tooltip.Decorate(tooltip, nil)
    ns.Tooltip.Decorate(tooltip, "200")
    withActiveList(ns, INDEX, nil)
    ns.Tooltip.Decorate(tooltip, 200)
    t.eq(tooltip.calls, {})

    local secretNs, secretStubs = wow.load({ issecretvalue = function() return true end })
    withActiveList(secretNs, INDEX, "My List")
    secretNs.Tooltip.Decorate(tooltip, 200)
    t.eq(tooltip.calls, {})
    t.eq(stubs.printed, {})
    t.eq(secretStubs.printed, {})
  end,

  ["a Lua error inside Decorate is caught and printed once"] = function(t)
    local ns, stubs = wow.load()
    withActiveList(ns, INDEX, "My List")
    local broken = { AddLine = function() error("boom") end }
    ns.Tooltip.Decorate(broken, 200)
    ns.Tooltip.Decorate(broken, 200)
    t.eq(#stubs.printed, 1)
    t.ok(stubs.printed[1]:find("^BIS List Tooltip: .*boom"))
  end,

  ["Install registers an item post call that decorates by data.id"] = function(t)
    local ns, stubs = wow.load()
    withActiveList(ns, INDEX, "My List")
    ns.Tooltip.Install()
    t.eq(#stubs.tooltipCallbacks, 1)
    t.eq(stubs.tooltipCallbacks[1].dataType, Enum.TooltipDataType.Item)
    local tooltip = fakeTooltip()
    stubs.tooltipCallbacks[1].callback(tooltip, { id = 200 })
    t.eq(#tooltip.calls, 4)
    stubs.tooltipCallbacks[1].callback(tooltip, nil)
    t.eq(#tooltip.calls, 4)
  end,

  ["a hover looks up the active list once"] = function(t)
    local ns = wow.load()
    local body = table.concat({
      table.concat({ "H", "a", "1", "1761782400", "forever", "Alpha", "Author" }, "\t"),
      "E\tMAGE\tFire\t200\thead\t1\tBest",
    }, "\n")
    ns.BuiltinLists = { { listId = "a", version = 1, publishedAt = 1761782400, title = "Alpha", author = "Author", importString = require("helpers").encode(body) } }
    BISListTooltipCharDB = { displayClass = {}, activeListId = "a" }
    ns.Lists.Init({}, BISListTooltipCharDB)
    local lookups = 0
    local getActive = ns.Lists.GetActive
    ns.Lists.GetActive = function() lookups = lookups + 1; return getActive() end
    local tooltip = fakeTooltip()
    ns.Tooltip.Decorate(tooltip, 200)
    t.eq(#tooltip.calls, 4)
    t.eq(lookups, 1)
  end,
}
