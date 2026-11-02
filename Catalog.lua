local _, ns = ...

local CLASS_TOKENS = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

local CLASS_ORDER = {}
for position, token in ipairs(CLASS_TOKENS) do CLASS_ORDER[token] = position end

local CLASS_NAMES = {
  DRUID = "Druid",
  HUNTER = "Hunter",
  MAGE = "Mage",
  PALADIN = "Paladin",
  PRIEST = "Priest",
  ROGUE = "Rogue",
  SHAMAN = "Shaman",
  WARLOCK = "Warlock",
  WARRIOR = "Warrior",
}

local SLOT_GROUP_ORDER = {
  "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
  "finger", "trinket", "weapon", "main-hand", "off-hand", "two-hand", "ranged", "relic",
}

local SLOT_GROUPS = {}
for _, id in ipairs(SLOT_GROUP_ORDER) do SLOT_GROUPS[id] = true end

local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function isLeapYear(year)
  return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

-- Versions exceed 32 bits and the Windows client's %d is a 32-bit long, so the
-- version is only ever split by arithmetic and formatted in small parts.
local function splitVersion(version)
  local sequence = version % 1000
  local date = (version - sequence) / 1000
  local year = math.floor(date / 10000)
  local month = math.floor(date / 100) % 100
  local day = date % 100
  local daysInMonth = DAYS_IN_MONTH[month]
  if daysInMonth and month == 2 and isLeapYear(year) then daysInMonth = 29 end
  local isCalVer = version == math.floor(version) and sequence >= 1
    and year >= 1000 and year <= 9999
    and daysInMonth ~= nil and day >= 1 and day <= daysInMonth
  return isCalVer, year, month, day, sequence
end

local function isCalVer(version)
  if type(version) ~= "number" then return false end
  return (splitVersion(version))
end

local function formatVersion(version)
  local valid, year, month, day, sequence = splitVersion(version)
  if not valid then return string.format("%.0f", version) end
  return string.format("%d.%02d.%02d.%d", year, month, day, sequence)
end

ns.Catalog = {
  CLASS_TOKENS = CLASS_TOKENS,
  CLASS_ORDER = CLASS_ORDER,
  FormatVersion = formatVersion,
  IsCalVer = isCalVer,
  CLASS_NAMES = CLASS_NAMES,
  SLOT_GROUP_ORDER = SLOT_GROUP_ORDER,
  SLOT_GROUPS = SLOT_GROUPS,
}
