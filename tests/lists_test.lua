local wow = require("wow")
local decodeJson = require("json")
local helpers = require("helpers")

local FIXTURES = wow.root .. "/tests/fixtures/import-strings/"

local function readFile(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local function fixtureText(name) return readFile(FIXTURES .. name .. ".txt") end
local function fixtureJson(name) return decodeJson(readFile(FIXTURES .. name .. ".json")) end

local function listString(id, version, title, entryLines)
  local lines = { table.concat({ "H", id, tostring(version), "1761782400", "forever", title, "Author" }, "\t") }
  for _, line in ipairs(entryLines or {}) do lines[#lines + 1] = line end
  return helpers.encode(table.concat(lines, "\n"))
end

local function builtin(id, version, title, entryLines)
  return {
    listId = id, version = version, publishedAt = 1761782400, title = title, author = "Author",
    importString = listString(id, version, title, entryLines),
  }
end

local function setup(builtins, charDB)
  local ns, stubs = wow.load()
  ns.BuiltinLists = builtins or {}
  local db = {}
  charDB = charDB or {}
  ns.Lists.Init(db, charDB)
  return ns, db, charDB, stubs
end

local SKIPPED_SENTENCE = " 1 entries were skipped because this version of the addon doesn't know their class or slot. Update the addon to see them."

return {
  ["import stores, activates a new list, and reports skipped entries"] = function(t)
    local ns, db, charDB = setup()
    local ok, message = ns.Lists.Import(fixtureText("unknown-class"))
    t.ok(ok)
    t.eq(message, 'Imported "Unknown Class Fixture" (version 2025.10.30.2). It is now your active list.' .. SKIPPED_SENTENCE)
    t.eq(ns.Lists.GetActive().listId, "fixtureUnknown01")
    t.eq(charDB.activeListTitle, "Unknown Class Fixture")
    t.eq(ns.Lists.GetActive().source, "imported")
    t.eq(db.lists.fixtureUnknown01.source, nil)
    t.eq(db.lists.fixtureUnknown01.importString:find("%s"), nil)
  end,

  ["import messages show CalVer versions"] = function(t)
    local ns = setup()
    local ok, message = ns.Lists.Import(fixtureText("basic"))
    t.ok(ok)
    t.eq(message, 'Imported "Basic Fixture" (version 2025.10.30.1). It is now your active list.')
    t.eq({ ns.Lists.Import(fixtureText("basic")) }, { false, 'You already have version 2025.10.30.1 of "Basic Fixture".' })
    t.eq({ ns.Lists.Import(listString("fixtureBasic0001", 20251029001, "Basic Fixture")) },
      { false, 'You already have a newer version (2025.10.30.1) of "Basic Fixture".' })
  end,

  ["messages escape pipes in list titles"] = function(t)
    local ns = setup()
    local _, imported = ns.Lists.Import(listString("p", 1, "A|cffff0000B"))
    t.eq(imported, 'Imported "A||cffff0000B" (version 1). It is now your active list.')
    t.eq(select(2, ns.Lists.Import(listString("p", 1, "A|cffff0000B"))), 'You already have version 1 of "A||cffff0000B".')
  end,

  ["fallback messages escape pipes in list titles"] = function(t)
    local ns = setup({ builtin("a", 1, "R|y") }, { activeListId = "gone", activeListTitle = "Q|x" })
    t.eq(ns.Lists.EnsureActive(), '"Q||x" was removed, so BIS List Tooltip is now using "R||y".')
  end,

  ["blank and malformed text return the decoder messages"] = function(t)
    local ns = setup()
    local messages = ns.ImportString.ERROR_MESSAGES
    t.eq({ ns.Lists.Import("") }, { false, messages.empty })
    t.eq({ ns.Lists.Import(" \n\t ") }, { false, messages.empty })
    t.eq({ ns.Lists.Import(nil) }, { false, messages.empty })
    t.eq({ ns.Lists.Import("hello") }, { false, messages.prefix })
  end,

  ["import refuses equal and older versions with the exact messages"] = function(t)
    local ns = setup()
    t.ok(ns.Lists.Import(listString("a", 3, "Alpha")))
    t.eq({ ns.Lists.Import(listString("a", 3, "Alpha")) }, { false, 'You already have version 3 of "Alpha".' })
    t.eq({ ns.Lists.Import(listString("a", 2, "Alpha")) }, { false, 'You already have a newer version (3) of "Alpha".' })
    t.eq(ns.Lists.HeldVersion("a"), 3)
  end,

  ["a newer import replaces the stored one and keeps the active choice"] = function(t)
    local ns, _, charDB = setup()
    ns.Lists.Import(listString("a", 1, "Alpha"))
    ns.Lists.Import(listString("b", 1, "Beta"))
    ns.Lists.SetActive("a")
    local ok, message = ns.Lists.Import(listString("b", 2, "Beta"))
    t.ok(ok)
    t.eq(message, 'Imported "Beta" (version 2).')
    t.eq(ns.Lists.Get("b").version, 2)
    t.eq(charDB.activeListId, "a")
  end,

  ["imported version above a built-in's wins in All(); equal goes to built-in"] = function(t)
    local ns = setup({ builtin("a", 2, "Alpha"), builtin("b", 1, "Beta") })
    t.eq({ ns.Lists.Import(listString("a", 2, "Alpha")) }, { false, 'You already have version 2 of "Alpha".' })
    t.eq(({ ns.Lists.Import(listString("b", 1, "Beta Imported")) })[1], false)
    ns.Lists.Import(listString("a", 3, "Alpha Imported"))
    local lists = ns.Lists.All()
    t.eq(#lists, 2)
    t.eq({ lists[1].listId, lists[1].source, lists[1].version }, { "a", "imported", 3 })
    t.eq({ lists[2].listId, lists[2].source }, { "b", "builtin" })
  end,

  ["All() orders built-ins first, then imported by title and id"] = function(t)
    local ns = setup({ builtin("z", 1, "Zed"), builtin("y", 1, "Why") })
    ns.Lists.Import(listString("i2", 1, "beta"))
    ns.Lists.Import(listString("i1", 1, "Alpha"))
    ns.Lists.Import(listString("i0", 1, "Beta"))
    local ids = {}
    for _, record in ipairs(ns.Lists.All()) do ids[#ids + 1] = record.listId end
    t.eq(ids, { "z", "y", "i1", "i0", "i2" })
  end,

  ["Remove refuses built-ins and removes imported lists for the account"] = function(t)
    local ns, db = setup({ builtin("a", 1, "Alpha") })
    ns.Lists.Import(listString("b", 1, "Beta"))
    t.eq(ns.Lists.Remove("a"), false)
    t.eq(ns.Lists.Remove("nope"), false)
    t.eq(ns.Lists.Remove("b"), true)
    t.eq(db.lists.b, nil)
    t.eq(ns.Lists.Get("b"), nil)
    t.ok(ns.Lists.Get("a"))
  end,

  ["EnsureActive falls back with the removal message on another character"] = function(t)
    local ns, _, charDB = setup({ builtin("a", 1, "Alpha") },
      { activeListId = "gone", activeListTitle = "Guild List" })
    t.eq(ns.Lists.EnsureActive(), '"Guild List" was removed, so BIS List Tooltip is now using "Alpha".')
    t.eq(charDB.activeListId, "a")
    t.eq(ns.Lists.EnsureActive(), nil)
  end,

  ["EnsureActive picks the first list silently when none was chosen"] = function(t)
    local ns, _, charDB = setup({ builtin("a", 1, "Alpha") })
    t.eq(ns.Lists.EnsureActive(), nil)
    t.eq(charDB.activeListId, "a")
    t.eq(charDB.activeListTitle, "Alpha")
  end,

  ["EnsureActive with nothing held returns the no-list message and GetActiveIndex is nil"] = function(t)
    local ns = setup({}, { activeListId = "gone", activeListTitle = "Guild List" })
    t.eq(ns.Lists.EnsureActive(), '"Guild List" was removed, so no list is active.')
    t.eq(ns.Lists.GetActive(), nil)
    t.eq(ns.Lists.GetActiveIndex(), nil)
  end,

  ["BuildIndex totals and order"] = function(t)
    local ns = setup()
    local index = ns.Lists.BuildIndex(fixtureJson("basic"))
    t.eq(index[19019], { { classToken = "MAGE", build = "Fire", label = "Best", rank = 1, total = 2, slotGroup = "head", buildPosition = 1 } })
    t.eq(index[19020], { { classToken = "MAGE", build = "Fire", label = "Pre-BIS", rank = 2, total = 2, slotGroup = "head", buildPosition = 1 } })
    t.eq(index[19022][1].total, 1)
  end,

  ["an item wanted by several builds is ordered by class, then first appearance, then rank"] = function(t)
    local ns = setup()
    local entries = {
      "E\tROGUE\tRogue\t5\thead\t1\tR",
      "E\tMAGE\tFrost\t5\thead\t2\tF2",
      "E\tMAGE\tArcane\t5\tneck\t1\tA1",
      "E\tMAGE\tfrost\t5\tneck\t1\tF1",
      "E\tMAGE\tFrost\t6\thead\t1\tOther",
    }
    local payload = ns.ImportString.Decode(listString("multi", 1, "Multi", entries))
    local item = ns.Lists.BuildIndex(payload)[5]
    local summary = {}
    for _, entry in ipairs(item) do summary[#summary + 1] = entry.classToken .. ":" .. entry.build .. ":" .. entry.label .. ":" .. entry.rank .. "/" .. entry.total end
    t.eq(summary, { "MAGE:frost:F1:1/1", "MAGE:Frost:F2:2/2", "MAGE:Arcane:A1:1/1", "ROGUE:Rogue:R:1/1" })
  end,

  ["one item in both weapon and off-hand of a build gives two entries"] = function(t)
    local ns = setup()
    local entries = {
      "E\tROGUE\tCombat\t7\tweapon\t1\tBest",
      "E\tROGUE\tCombat\t7\toff-hand\t1\tBest",
    }
    local item = ns.Lists.BuildIndex(ns.ImportString.Decode(listString("dual", 1, "Dual", entries)))[7]
    t.eq(#item, 2)
    t.eq({ item[1].slotGroup, item[2].slotGroup }, { "weapon", "off-hand" })
  end,

  ["GetActiveIndex builds from the active list and refreshes after a newer import"] = function(t)
    local ns = setup()
    ns.Lists.Import(fixtureText("basic"))
    t.eq(ns.Lists.GetActiveIndex()[19019][1].label, "Best")
    t.eq(ns.Lists.GetActiveIndex(), ns.Lists.GetActiveIndex())
    ns.Lists.Import(listString("fixtureBasic0001", 20251030002, "Basic Fixture", { "E\tMAGE\tFire\t77\thead\t1\tNew" }))
    local index = ns.Lists.GetActiveIndex()
    t.eq(index[19019], nil)
    t.eq(index[77][1].label, "New")
  end,

  ["OnChange fires for import, remove and active"] = function(t)
    local ns = setup()
    local seen = {}
    ns.Lists.OnChange(function(reason, listId) seen[#seen + 1] = reason .. ":" .. tostring(listId) end)
    ns.Lists.Import(listString("a", 1, "Alpha"))
    ns.Lists.Import(listString("b", 1, "Beta"))
    ns.Lists.SetActive("b")
    ns.Lists.SetActive("unknown")
    ns.Lists.Remove("a")
    t.eq(seen, { "import:a", "import:b", "active:b", "remove:a" })
  end,

  ["EnsureActive uses the id as the title when no title was stored"] = function(t)
    local ns = setup({ builtin("a", 1, "Alpha") }, { activeListId = "gone" })
    t.eq(ns.Lists.EnsureActive(), '"gone" was removed, so BIS List Tooltip is now using "Alpha".')
  end,

  ["re-importing the active list at a newer version refreshes the stored title"] = function(t)
    local ns, _, charDB = setup()
    ns.Lists.Import(listString("a", 1, "Alpha"))
    ns.Lists.Import(listString("a", 2, "Alpha Renamed"))
    t.eq(charDB.activeListTitle, "Alpha Renamed")
  end,

  ["a throwing listener neither aborts the change nor skips later listeners"] = function(t)
    local ns, db, _, stubs = setup()
    local calls = 0
    ns.Lists.OnChange(function() error("boom") end)
    ns.Lists.OnChange(function() calls = calls + 1 end)
    t.ok(ns.Lists.Import(listString("a", 1, "Alpha")))
    t.ok(db.lists.a)
    t.eq(calls, 1)
    t.eq(#stubs.printed, 1)
    t.ok(stubs.printed[1]:find("boom", 1, true))
  end,

  ["listener errors go to geterrorhandler when it exists"] = function(t)
    local ns = setup()
    local reported = {}
    _G.geterrorhandler = function() return function(message) reported[#reported + 1] = message end end
    ns.Lists.OnChange(function() error("boom") end)
    ns.Lists.Import(listString("a", 1, "Alpha"))
    t.eq(#reported, 1)
    t.ok(reported[1]:find("boom", 1, true))
  end,

  ["Off hides BIS lines on this character and remembers the list for turning them back on"] = function(t)
    local ns, _, charDB = setup()
    ns.Lists.Import(listString("a", 1, "Alpha", { "E\tMAGE\tFire\t11\thead\t1\tA" }))
    local changes = {}
    ns.Lists.OnChange(function(kind) changes[#changes + 1] = kind end)
    ns.Lists.SetOff()
    t.ok(ns.Lists.IsOff())
    t.eq(ns.Lists.GetActive(), nil)
    t.eq(ns.Lists.GetActiveIndex(), nil)
    t.eq(charDB.activeListId, "a")
    t.eq(ns.Lists.EnsureActive(), nil)
    t.ok(ns.Lists.IsOff())
    t.eq(changes, { "active" })
    ns.Lists.SetActive("a")
    t.eq(ns.Lists.IsOff(), false)
    t.ok(ns.Lists.GetActiveIndex()[11])
  end,

  ["importing a new list turns BIS lines back on with that list"] = function(t)
    local ns = setup()
    ns.Lists.Import(listString("a", 1, "Alpha"))
    ns.Lists.SetOff()
    ns.Lists.Import(listString("b", 1, "Beta"))
    t.eq(ns.Lists.IsOff(), false)
    t.eq(ns.Lists.GetActive().listId, "b")
  end,

  ["Off is per character"] = function(t)
    local ns = setup({ builtin("a", 1, "Alpha") })
    ns.Lists.SetOff()
    local other = setup({ builtin("a", 1, "Alpha") })
    t.eq(other.Lists.IsOff(), false)
    other.Lists.EnsureActive()
    t.eq(other.Lists.GetActive().listId, "a")
  end,

  ["SetActive switching lists changes what GetActiveIndex returns"] = function(t)
    local ns = setup()
    ns.Lists.Import(listString("a", 1, "Alpha", { "E\tMAGE\tFire\t11\thead\t1\tA" }))
    ns.Lists.Import(listString("b", 1, "Beta", { "E\tMAGE\tFire\t22\thead\t1\tB" }))
    ns.Lists.SetActive("a")
    t.ok(ns.Lists.GetActiveIndex()[11])
    ns.Lists.SetActive("b")
    local index = ns.Lists.GetActiveIndex()
    t.eq(index[11], nil)
    t.eq(index[22][1].label, "B")
  end,

  ["removing the active list falls back at once and notifies active after remove"] = function(t)
    local ns, _, charDB = setup({ builtin("a", 1, "Alpha") })
    ns.Lists.Import(listString("b", 1, "Be|ta", { "E\tMAGE\tFire\t11\thead\t1\tB" }))
    t.eq(charDB.activeListId, "b")
    local seen = {}
    ns.Lists.OnChange(function(reason, listId) seen[#seen + 1] = reason .. ":" .. tostring(listId) end)
    local ok, message = ns.Lists.Remove("b")
    t.eq(ok, true)
    t.eq(message, '"Be||ta" was removed, so BIS List Tooltip is now using "Alpha".')
    t.eq(charDB.activeListId, "a")
    t.eq(charDB.activeListTitle, "Alpha")
    t.eq(seen, { "remove:b", "active:a" })
    t.eq(ns.Lists.GetActive().listId, "a")
    t.eq(ns.Lists.EnsureActive(), nil)
  end,

  ["removing the only list leaves no active list"] = function(t)
    local ns, _, charDB = setup()
    ns.Lists.Import(listString("b", 1, "Beta"))
    local seen = {}
    ns.Lists.OnChange(function(reason, listId) seen[#seen + 1] = reason .. ":" .. tostring(listId) end)
    local _, message = ns.Lists.Remove("b")
    t.eq(message, '"Beta" was removed, so no list is active.')
    t.eq(charDB.activeListId, nil)
    t.eq(ns.Lists.GetActive(), nil)
    t.eq(seen, { "remove:b", "active:nil" })
  end,

  ["removing a list that is not active gives no message and no active change"] = function(t)
    local ns, _, charDB = setup({ builtin("a", 1, "Alpha") })
    ns.Lists.Import(listString("b", 1, "Beta"))
    ns.Lists.SetActive("a")
    local seen = {}
    ns.Lists.OnChange(function(reason, listId) seen[#seen + 1] = reason .. ":" .. tostring(listId) end)
    local ok, message = ns.Lists.Remove("b")
    t.eq(ok, true)
    t.eq(message, nil)
    t.eq(charDB.activeListId, "a")
    t.eq(seen, { "remove:b" })
  end,

  ["a failed decode of the active list is cached, not retried on every call"] = function(t)
    local bad = builtin("a", 1, "Alpha")
    bad.importString = "not an import string"
    local ns = setup({ bad })
    ns.Lists.EnsureActive()
    local decodes = 0
    local decode = ns.ImportString.Decode
    ns.ImportString.Decode = function(...) decodes = decodes + 1; return decode(...) end
    t.eq(ns.Lists.GetActiveIndex(), nil)
    t.eq(ns.Lists.GetActiveIndex(), nil)
    t.eq(decodes, 1)
  end,
}
