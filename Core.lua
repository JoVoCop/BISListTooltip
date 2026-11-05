local _, ns = ...

ns.ADDON_NAME = "BISListTooltip"
ns.SITE_URL = "https://bislist.io"

local PREFIX = "BIS List Tooltip: "
local listsReady = false

local function ensureTable(value)
  if type(value) == "table" then return value end
  return {}
end

local function fillDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if target[key] == nil then target[key] = value end
  end
end

local function setUpSavedVariables()
  BISListTooltipDB = ensureTable(BISListTooltipDB)
  fillDefaults(BISListTooltipDB, { schema = 1, noticesEnabled = true, blankLineBefore = true, blankLineAfter = true })
  BISListTooltipDB.lists = ensureTable(BISListTooltipDB.lists)
  BISListTooltipDB.notified = ensureTable(BISListTooltipDB.notified)

  BISListTooltipCharDB = ensureTable(BISListTooltipCharDB)
  local firstLoad = type(BISListTooltipCharDB.displayClass) ~= "table"
  BISListTooltipCharDB.displayClass = ensureTable(BISListTooltipCharDB.displayClass)

  if firstLoad then
    for _, token in ipairs(ns.Catalog.CLASS_TOKENS) do
      BISListTooltipCharDB.displayClass[token] = true
    end
  end
end

-- One failing module must not stop the others or the tooltip from loading.
local function isolatedInit(module)
  local function report(failure)
    if geterrorhandler then return geterrorhandler()(failure) end
    print(PREFIX .. tostring(failure))
  end
  xpcall(module.Init, report)
end

local function onAddonLoaded()
  setUpSavedVariables()
  ns.Lists.Init(BISListTooltipDB, BISListTooltipCharDB)
  ns.Tooltip.Install()
  listsReady = true
  isolatedInit(ns.Comms)
  isolatedInit(ns.Notices)
  isolatedInit(ns.Options)
end

local function onPlayerLogin()
  if not listsReady then return end
  local message = ns.Lists.EnsureActive()
  if message then print(PREFIX .. message) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, loadedName)
  if event == "ADDON_LOADED" then
    if loadedName == ns.ADDON_NAME then onAddonLoaded() end
  elseif event == "PLAYER_LOGIN" then
    onPlayerLogin()
  end
end)

SLASH_BISLISTTOOLTIP1 = "/blt"
SlashCmdList["BISLISTTOOLTIP"] = function()
  if ns.Options and ns.Options.Open then ns.Options.Open() end
end
