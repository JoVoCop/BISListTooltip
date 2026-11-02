-- WoW API stubs and an addon loader that follows the TOC.

local wow = { root = "." }

local ADDON_NAME = "BISListTooltip"

-- Captured at require time, before any stub or addon file touches _G, so each
-- load() can put the global table back to a pristine state.
local pristine = {}
for key, value in pairs(_G) do pristine[key] = value end

local CLASS_COLORS = {
  WARRIOR = { 0.78, 0.61, 0.43, "ffc79c6e" },
  PALADIN = { 0.96, 0.55, 0.73, "fff58cba" },
  HUNTER = { 0.67, 0.83, 0.45, "ffabd473" },
  ROGUE = { 1.00, 0.96, 0.41, "fffff569" },
  PRIEST = { 1.00, 1.00, 1.00, "ffffffff" },
  SHAMAN = { 0.00, 0.44, 0.87, "ff0070de" },
  MAGE = { 0.25, 0.78, 0.92, "ff40c7eb" },
  WARLOCK = { 0.53, 0.53, 0.93, "ff8788ee" },
  DRUID = { 1.00, 0.49, 0.04, "ffff7d0a" },
}

local function restorePristineGlobals()
  for key in pairs(_G) do
    if pristine[key] == nil then _G[key] = nil end
  end
  for key, value in pairs(pristine) do _G[key] = value end
end

local function readTocPaths(root)
  local file, openError = io.open(root .. "/" .. ADDON_NAME .. ".toc", "r")
  if not file then error("cannot open TOC: " .. tostring(openError), 0) end
  local paths = {}
  for line in file:lines() do
    local trimmed = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" and trimmed:sub(1, 2) ~= "##" and trimmed:sub(1, 1) ~= "#" then
      if trimmed:match("%.lua$") then
        paths[#paths + 1] = trimmed:gsub("\\", "/")
      end
    end
  end
  file:close()
  return paths
end

local function newStubs()
  local stubs = {
    timers = {},
    sent = {},
    printed = {},
    popups = {},
    categories = {},
    registered = {},
    opened = {},
    tooltipCallbacks = {},
    frames = {},
    now = 1761782400,
    state = {
      inCombat = false,
      inInstance = false,
      inGuild = true,
      playerName = "Tester",
      playerClass = "MAGE",
    },
  }

  function stubs.advance(seconds)
    local target = stubs.now + seconds
    while true do
      local dueIndex
      for index, timer in ipairs(stubs.timers) do
        if timer.due <= target and (not dueIndex or timer.due < stubs.timers[dueIndex].due) then
          dueIndex = index
        end
      end
      if not dueIndex then break end
      local timer = table.remove(stubs.timers, dueIndex)
      -- Callbacks must observe their own due time, as in the real client.
      if timer.due > stubs.now then stubs.now = timer.due end
      timer.callback()
    end
    stubs.now = target
  end

  function stubs.fire(event, ...)
    for _, frame in ipairs(stubs.frames) do
      local handler = frame.scripts.OnEvent
      if handler and frame.events[event] then handler(frame, event, ...) end
    end
  end

  return stubs
end

local function newFrame(stubs)
  local frame = { events = {}, scripts = {}, shown = true, last = {} }
  function frame.Show(self) self.shown = true end
  function frame.Hide(self) self.shown = false end
  function frame.SetShown(self, shown) self.shown = shown and true or false end
  function frame.IsShown(self) return self.shown end
  function frame.RegisterEvent(self, event) self.events[event] = true end
  function frame.UnregisterEvent(self, event) self.events[event] = nil end
  function frame.SetScript(self, name, handler) self.scripts[name] = handler end
  function frame.GetScript(self, name) return self.scripts[name] end
  function frame.CreateFontString() return newFrame(stubs) end
  -- XML parentKey children that real templates provide.
  for _, key in ipairs({ "Text", "EditBox", "CharCount" }) do
    frame[key] = setmetatable({ events = {}, scripts = {} }, { __index = function() return function() end end })
  end
  setmetatable(frame, {
    -- Unknown methods are accepted and their latest arguments kept for assertions.
    __index = function(self, key)
      return function(_, ...) rawget(self, "last")[key] = { ... } end
    end,
  })
  stubs.frames[#stubs.frames + 1] = frame
  return frame
end

local function installStubs(stubs)
  local state = stubs.state

  -- WoW exposes these Lua standard-library aliases as globals.
  local aliases = {
    strmatch = string.match, strfind = string.find, strsub = string.sub, strlen = string.len,
    strlower = string.lower, strupper = string.upper, strrep = string.rep, strbyte = string.byte,
    strchar = string.char, gsub = string.gsub, gmatch = string.gmatch, format = string.format,
    tinsert = table.insert, tremove = table.remove, sort = table.sort, wipe = function(t)
      for key in pairs(t) do t[key] = nil end
      return t
    end,
    floor = math.floor, ceil = math.ceil, abs = math.abs, max = math.max, min = math.min,
  }
  for name, fn in pairs(aliases) do _G[name] = fn end

  _G.CreateFrame = function() return newFrame(stubs) end

  _G.C_Timer = {
    After = function(delay, callback)
      stubs.timers[#stubs.timers + 1] = { due = stubs.now + delay, callback = callback }
    end,
  }

  _G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, message, channel, target)
      stubs.sent[#stubs.sent + 1] = { prefix = prefix, message = message, channel = channel, target = target }
      return 0
    end,
  }

  _G.GetTime = function() return stubs.now end
  _G.time = function() return math.floor(stubs.now) end
  _G.date = os.date
  _G.GetServerTime = function() return math.floor(stubs.now) end

  _G.UnitClass = function()
    local token = state.playerClass
    return token:sub(1, 1) .. token:sub(2):lower(), token
  end
  _G.UnitName = function() return state.playerName end
  _G.IsInGuild = function() return state.inGuild end
  _G.IsInInstance = function()
    return state.inInstance, state.inInstance and "party" or "none"
  end
  _G.InCombatLockdown = function() return state.inCombat end

  _G.Ambiguate = function(name, context)
    if context == "short" then return (name:gsub("%-.*$", "")) end
    return name
  end

  local colors = {}
  for token, color in pairs(CLASS_COLORS) do
    colors[token] = { r = color[1], g = color[2], b = color[3], colorStr = color[4] }
  end
  _G.RAID_CLASS_COLORS = colors

  local function record(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
    stubs.printed[#stubs.printed + 1] = table.concat(parts, " ")
  end
  _G.print = record
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) stubs.printed[#stubs.printed + 1] = text end }

  _G.StaticPopupDialogs = {}
  _G.StaticPopup_Show = function(which, text1, text2, data)
    local dialog = { editBox = { text = nil } }
    function dialog.GetEditBox(self) return self.editBox end
    function dialog.editBox.SetText(self, text) self.text = text end
    local popup = { which = which, args = { text1, text2, data }, data = data, dialog = dialog, shown = true }
    stubs.popups[#stubs.popups + 1] = popup
    local definition = StaticPopupDialogs[which]
    if definition and definition.OnShow then definition.OnShow(dialog, data) end
    return dialog
  end
  stubs.hidePopup = function(popup)
    popup.shown = false
    local definition = StaticPopupDialogs[popup.which]
    if definition and definition.OnHide then definition.OnHide(popup.dialog, popup.data) end
  end

  stubs.acceptPopup = function(popup)
    local definition = StaticPopupDialogs[popup.which]
    if definition and definition.OnAccept then definition.OnAccept(popup.dialog, popup.data) end
    stubs.hidePopup(popup)
  end

  _G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
      local category = { panel = panel, name = name, ID = name }
      function category.GetID(self) return self.ID end
      stubs.categories[#stubs.categories + 1] = category
      return category
    end,
    RegisterAddOnCategory = function(category) stubs.registered[#stubs.registered + 1] = category end,
    OpenToCategory = function(id) stubs.opened[#stubs.opened + 1] = id end,
  }

  _G.TooltipDataProcessor = {
    AddTooltipPostCall = function(dataType, callback)
      stubs.tooltipCallbacks[#stubs.tooltipCallbacks + 1] = { dataType = dataType, callback = callback }
    end,
  }
  _G.Enum = { TooltipDataType = { Item = 0 } }

  _G.CreateAtlasMarkup = function(atlas) return "|A:" .. atlas .. "|a" end
  _G.SlashCmdList = {}
end

-- Pass false for an override to remove that global, to test missing APIs.
function wow.load(overrides)
  restorePristineGlobals()
  local stubs = newStubs()
  installStubs(stubs)

  for name, value in pairs(overrides or {}) do
    if value == false then _G[name] = nil else _G[name] = value end
  end

  local ns = {}
  for _, path in ipairs(readTocPaths(wow.root)) do
    local chunk, loadError = loadfile(wow.root .. "/" .. path)
    if not chunk then error(loadError, 0) end
    chunk(ADDON_NAME, ns)
  end
  return ns, stubs
end

return wow
