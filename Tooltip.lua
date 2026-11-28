local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local HEADER_COLOR = "|cff0af5a2"
local ICON_SIZE = 14
local errorReported = false

local slotOrder = {}
for position, id in ipairs(ns.Catalog.SLOT_GROUP_ORDER) do slotOrder[id] = position end

-- Build, label and list title are author-written; a raw "|" would be parsed as a colour or texture escape.
local function escapePipes(text)
  return (tostring(text):gsub("|", "||"))
end

local function iconMarkup(classToken)
  if not CreateAtlasMarkup then return "" end
  return CreateAtlasMarkup("classicon-" .. classToken:lower(), ICON_SIZE, ICON_SIZE)
end

-- An entry with a bonus (a random suffix) only matches an item carrying that bonus; with no bonus IDs
-- known, only entries for any version of the item match.
local function matchesBonus(entry, bonusIds)
  return entry.bonusId == nil or (bonusIds ~= nil and bonusIds[entry.bonusId] == true)
end

-- A token's own bonus IDs say nothing about the reward's suffix, so reward entries are not filtered.
local function collectEntries(itemId, index, tokenRewards, bonusIds)
  local entries = {}
  for _, entry in ipairs(index[itemId] or {}) do
    if matchesBonus(entry, bonusIds) then entries[#entries + 1] = entry end
  end
  for _, rewardId in ipairs(tokenRewards and tokenRewards[itemId] or {}) do
    for _, entry in ipairs(index[rewardId] or {}) do entries[#entries + 1] = entry end
  end
  return entries
end

-- Item strings are itemID:enchant:gem1-4:suffix:unique:level:spec:modifiers:context:numBonusIDs:bonusIDs...
-- The match skips the colour code in front of a full hyperlink, which has a colon of its own.
function Tooltip.LinkBonusIds(link, itemId)
  if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return nil end
  local itemString = link:match("item:([%-%d:]+)")
  if not itemString then return nil end
  local fields = {}
  for field in (itemString .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
  if tonumber(fields[1]) ~= itemId then return nil end
  local bonusIds = {}
  for position = 14, math.min(13 + (tonumber(fields[13]) or 0), #fields) do
    local bonusId = tonumber(fields[position])
    if bonusId then bonusIds[bonusId] = true end
  end
  return bonusIds
end

local function tooltipLink(tooltip, data)
  if type(tooltip.GetItem) == "function" then
    local succeeded, _, link = pcall(tooltip.GetItem, tooltip)
    if succeeded and link ~= nil then return link end
  end
  return data and data.hyperlink
end

local function removeDuplicates(entries)
  local seen, unique = {}, {}
  for _, entry in ipairs(entries) do
    local key = table.concat({ entry.classToken, entry.build:lower(), entry.slotGroup, entry.label, entry.rank, entry.total }, "\0")
    if not seen[key] then
      seen[key] = true
      unique[#unique + 1] = entry
    end
  end
  return unique
end

function Tooltip.BuildLines(itemId, index, tokenRewards, displayClass, bonusIds)
  local classOrder = ns.Catalog.CLASS_ORDER

  local shown = {}
  for _, entry in ipairs(removeDuplicates(collectEntries(itemId, index, tokenRewards, bonusIds))) do
    if classOrder[entry.classToken] and displayClass[entry.classToken] ~= false then
      shown[#shown + 1] = entry
    end
  end

  table.sort(shown, function(a, b)
    if a.classToken ~= b.classToken then return (classOrder[a.classToken] or math.huge) < (classOrder[b.classToken] or math.huge) end
    if a.buildPosition ~= b.buildPosition then return a.buildPosition < b.buildPosition end
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.label ~= b.label then return a.label < b.label end
    return (slotOrder[a.slotGroup] or math.huge) < (slotOrder[b.slotGroup] or math.huge)
  end)

  local lines = {}
  for _, entry in ipairs(shown) do
    local icon = iconMarkup(entry.classToken)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classToken]
    lines[#lines + 1] = {
      left = (icon ~= "" and icon .. " " or "") .. escapePipes(entry.build) .. (entry.slotGroup == "off-hand" and " (Off Hand)" or ""),
      right = escapePipes(entry.label) .. " - " .. entry.rank .. "/" .. entry.total,
      r = color and color.r or 1,
      g = color and color.g or 1,
      b = color and color.b or 1,
    }
  end
  return lines
end

local function decorate(tooltip, itemId, data)
  if type(itemId) ~= "number" then return end
  -- Restricted content hands out secret values that must not be used as table keys.
  if issecretvalue and issecretvalue(itemId) then return end

  local record = ns.Lists.GetActive()
  if not record then return end
  local index = ns.Lists.GetActiveIndex(record)
  if not index then return end

  local displayClass = BISListTooltipCharDB and BISListTooltipCharDB.displayClass or {}
  local bonusIds = Tooltip.LinkBonusIds(tooltipLink(tooltip, data), itemId)
  local lines = Tooltip.BuildLines(itemId, index, ns.TokenRewards, displayClass, bonusIds)
  if #lines == 0 then return end

  local db = BISListTooltipDB or {}
  if db.blankLineBefore ~= false then tooltip:AddLine(" ") end
  tooltip:AddLine(HEADER_COLOR .. escapePipes(record.title) .. "|r")
  for _, line in ipairs(lines) do
    tooltip:AddDoubleLine(line.left, line.right, line.r, line.g, line.b, line.r, line.g, line.b)
  end
  if db.blankLineAfter ~= false then tooltip:AddLine(" ") end
end

function Tooltip.Decorate(tooltip, itemId, data)
  local succeeded, message = pcall(decorate, tooltip, itemId, data)
  if succeeded or errorReported then return end
  errorReported = true
  print("BIS List Tooltip: " .. tostring(message))
end

function Tooltip.Install()
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item) then
    print("BIS List Tooltip: this game client has no item tooltip hook, so tooltips are disabled.")
    return
  end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    ns.Tooltip.Decorate(tooltip, data and data.id, data)
  end)
end
