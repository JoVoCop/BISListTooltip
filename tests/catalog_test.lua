local wow = require("wow")

local README = wow.root .. "/tests/fixtures/import-strings/README.md"

local function readReadme()
  local file, openError = io.open(README, "r")
  if not file then error("cannot open fixtures README: " .. tostring(openError), 0) end
  local text = file:read("*a")
  file:close()
  return text
end

-- Words in the fenced block that follows a heading in the fixtures README.
local function wordsAfter(heading)
  local text = readReadme()
  local start = text:find(heading, 1, true)
  if not start then error("heading not found in fixtures README: " .. heading, 0) end
  local block = text:match("```\n(.-)```", start)
  if not block then error("no fenced block after heading: " .. heading, 0) end
  local words = {}
  for word in block:gmatch("%S+") do words[#words + 1] = word end
  return words
end

local function classNamesFromTokens(catalog)
  local names = {}
  for _, token in ipairs(catalog.CLASS_TOKENS) do names[#names + 1] = catalog.CLASS_NAMES[token] end
  return names
end

return {
  ["class tokens and order match the fixtures README"] = function(t)
    local catalog = wow.load().Catalog
    t.eq(catalog.CLASS_TOKENS, wordsAfter("Class tokens, in order:"))
    for position, token in ipairs(catalog.CLASS_TOKENS) do
      t.eq(catalog.CLASS_ORDER[token], position)
    end
  end,

  ["slot groups match the fixtures README"] = function(t)
    local catalog = wow.load().Catalog
    t.eq(catalog.SLOT_GROUP_ORDER, wordsAfter("Slot group ids, in order:"))
    for _, id in ipairs(catalog.SLOT_GROUP_ORDER) do
      t.ok(catalog.SLOT_GROUPS[id], "SLOT_GROUPS has " .. id)
    end
  end,

  ["9 classes, 18 slot groups, no spec table"] = function(t)
    local catalog = wow.load().Catalog
    t.eq(#catalog.CLASS_TOKENS, 9)
    t.eq(#catalog.SLOT_GROUP_ORDER, 18)
    t.eq(catalog.SPECS, nil)
    t.eq(catalog.SPEC_BY_ID, nil)
    t.eq(catalog.SPEC_ORDER, nil)
    for _, token in ipairs(catalog.CLASS_TOKENS) do t.ok(catalog.CLASS_NAMES[token], token) end
  end,

  ["class names follow the class token order"] = function(t)
    local catalog = wow.load().Catalog
    t.eq(classNamesFromTokens(catalog),
      { "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior" })
  end,

  ["FormatVersion shows CalVer as YYYY.MM.DD.N"] = function(t)
    local format = wow.load().Catalog.FormatVersion
    t.eq(format(20261104001), "2026.11.04.1")
    t.eq(format(20261231012), "2026.12.31.12")
    t.eq(format(20240229001), "2024.02.29.1")
    t.eq(format(20261104999), "2026.11.04.999")
  end,

  ["FormatVersion shows other integers as plain decimal"] = function(t)
    local format = wow.load().Catalog.FormatVersion
    t.eq(format(3), "3")
    t.eq(format(5), "5")
    t.eq(format(20261304001), "20261304001")
    t.eq(format(20260231001), "20260231001")
    t.eq(format(20261104000), "20261104000")
    t.eq(format(202611041000), "202611041000")
    t.eq(format(20230229001), "20230229001")
    t.eq(format(19000229001), "19000229001")
    t.eq(format(20000229001), "2000.02.29.1")
    t.eq(format(9990101001), "9990101001")
    t.eq(format(20261100001), "20261100001")
    t.eq(format(20261132001), "20261132001")
  end,

  ["IsCalVer accepts only real dates with a sequence of 1 to 999"] = function(t)
    local isCalVer = wow.load().Catalog.IsCalVer
    t.eq(isCalVer(20261104001), true)
    t.eq(isCalVer(20240229001), true)
    t.eq(isCalVer(20261104999), true)
    t.eq(isCalVer(999999999999), false)
    t.eq(isCalVer(20261104000), false)
    t.eq(isCalVer(20260231001), false)
    t.eq(isCalVer(5), false)
    t.eq(isCalVer(20261104001.5), false)
    t.eq(isCalVer("20261104001"), false)
    t.eq(isCalVer(nil), false)
  end,
}
