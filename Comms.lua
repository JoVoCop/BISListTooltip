local _, ns = ...

local Comms = {}
ns.Comms = Comms

local PREFIX = "BISLT"
local CHANNEL = "GUILD"
local MAX_MESSAGE_BYTES = 255
local MAX_ANNOUNCE_MESSAGES = 5
local MAX_ID_LENGTH = 32
local MAX_NUMBER_DIGITS = 12
local LOGIN_ANNOUNCE_DELAY = 20
local ANNOUNCE_SPACING = 1
local REPLY_MIN_DELAY, REPLY_MAX_DELAY = 2, 8
local REPLY_COOLDOWN = 60

local pendingAnnounceAll = false
-- C_Timer.After can't be cancelled, so a timer only acts if its token is still current.
local replyTokens = {}
local lastReplyAt = {}
local nextToken = 0

local function debugLog(text)
  if ns.debug then print("BISLT comms: " .. text) end
end

local function validId(listId)
  return type(listId) == "string" and #listId <= MAX_ID_LENGTH and listId:match("^[%w_%-]+$") ~= nil
end

local function wireNumber(value)
  if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then return nil end
  -- %d is a 32-bit long on the Windows client and would truncate 11-digit versions.
  local text = string.format("%.0f", value)
  if #text > MAX_NUMBER_DIGITS then return nil end
  return text
end

local function encodeItem(record)
  if not validId(record.listId) then return nil end
  local version, publishedAt = wireNumber(record.version), wireNumber(record.publishedAt)
  if not (version and publishedAt) then return nil end
  return record.listId .. ":" .. version .. ":" .. publishedAt
end

local function send(message)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
    debugLog("SendAddonMessage is unavailable")
    return
  end
  local result = C_ChatInfo.SendAddonMessage(PREFIX, message, CHANNEL)
  if result ~= nil and result ~= 0 then debugLog("send returned " .. tostring(result)) end
end

local function encode(kind, records)
  local messages, current = {}, nil
  local header = kind .. "1"
  for _, record in ipairs(records) do
    local item = encodeItem(record)
    if item then
      if current and #current + 1 + #item > MAX_MESSAGE_BYTES then
        messages[#messages + 1] = current
        current = nil
      end
      if not current then
        if #messages >= MAX_ANNOUNCE_MESSAGES then break end
        current = header
      end
      current = current .. " " .. item
    end
  end
  if current then messages[#messages + 1] = current end
  return messages
end

function Comms.EncodeAnnounce(records)
  return encode("A", records)
end

local SECONDS_PER_DAY = 86400

local function currentTime()
  if GetServerTime then return GetServerTime() end
  return time()
end

-- Notices persist the highest version seen per list, so an absurd one from a guildmate
-- would silence every real future notice. A day of slack covers clock and timezone skew.
local function parseItem(text)
  local listId, version, publishedAt = text:match("^([%w_%-]+):(%d+):(%d+)$")
  if not listId or #listId > MAX_ID_LENGTH then return nil end
  if #version > MAX_NUMBER_DIGITS or #publishedAt > MAX_NUMBER_DIGITS then return nil end
  version, publishedAt = tonumber(version), tonumber(publishedAt)
  if not ns.Catalog.IsCalVer(version) then return nil end
  local latest = currentTime() + SECONDS_PER_DAY
  if publishedAt > latest then return nil end
  if (version - version % 1000) / 1000 > tonumber(date("!%Y%m%d", latest)) then return nil end
  return { listId = listId, version = version, publishedAt = publishedAt }
end

function Comms.Parse(message)
  if type(message) ~= "string" or #message > MAX_MESSAGE_BYTES then return nil end
  local kind, rest = message:match("^([AV])1 (.+)$")
  if not kind then return nil end
  local items = {}
  local position = 1
  while position <= #rest + 1 do
    local spaceAt = rest:find(" ", position, true)
    local text = rest:sub(position, (spaceAt or #rest + 1) - 1)
    local item = parseItem(text)
    if not item then return nil end
    items[#items + 1] = item
    if not spaceAt then break end
    position = spaceAt + 1
  end
  return kind, items
end

local function canAnnounceNow()
  if not IsInGuild() then return false end
  if IsInInstance() then
    pendingAnnounceAll = true
    return false
  end
  return true
end

function Comms.AnnounceAll()
  if not canAnnounceNow() then return end
  pendingAnnounceAll = false
  local messages = Comms.EncodeAnnounce(ns.Lists.All())
  for index, message in ipairs(messages) do
    if index == 1 then
      send(message)
    else
      C_Timer.After((index - 1) * ANNOUNCE_SPACING, function()
        -- The player may have zoned into an instance since the first message went out.
        if IsInGuild() and canAnnounceNow() then send(message) end
      end)
    end
  end
end

function Comms.Announce(listId)
  if not canAnnounceNow() then return end
  local record = ns.Lists.Get(listId)
  if not record then return end
  local messages = Comms.EncodeAnnounce({ record })
  if messages[1] then send(messages[1]) end
end

local function scheduleReply(listId)
  if replyTokens[listId] then return end
  nextToken = nextToken + 1
  local token = nextToken
  replyTokens[listId] = token
  C_Timer.After(REPLY_MIN_DELAY + math.random() * (REPLY_MAX_DELAY - REPLY_MIN_DELAY), function()
    if replyTokens[listId] ~= token then return end
    replyTokens[listId] = nil
    if IsInInstance() or not IsInGuild() then return end
    local now = GetTime()
    if lastReplyAt[listId] and now - lastReplyAt[listId] < REPLY_COOLDOWN then return end
    local record = ns.Lists.Get(listId)
    if not record then return end
    lastReplyAt[listId] = now
    local messages = encode("V", { record })
    if messages[1] then send(messages[1]) end
  end)
end

local function handleItem(kind, item)
  local held = ns.Lists.HeldVersion(item.listId)
  if not held then return end
  if item.version > held and ns.Notices then
    ns.Notices.Offer(item.listId, item.version, item.publishedAt)
  end
  if kind == "A" and held > item.version then
    scheduleReply(item.listId)
  elseif item.version >= held then
    -- The sender of a newer or equal version has already reached the stale holder.
    replyTokens[item.listId] = nil
  end
end

function Comms.OnMessage(prefix, message, channel, sender)
  local ok, failure = pcall(function()
    if prefix ~= PREFIX or channel ~= CHANNEL or type(sender) ~= "string" then return end
    if Ambiguate(sender, "short") == UnitName("player") then return end
    local kind, items = Comms.Parse(message)
    if not kind then return end
    for _, item in ipairs(items) do handleItem(kind, item) end
  end)
  if not ok then debugLog("OnMessage failed: " .. tostring(failure)) end
end

local function onEvent(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    Comms.OnMessage(...)
  elseif event == "PLAYER_LOGIN" then
    C_Timer.After(LOGIN_ANNOUNCE_DELAY, Comms.AnnounceAll)
  elseif event == "PLAYER_ENTERING_WORLD" then
    if pendingAnnounceAll and not IsInInstance() then Comms.AnnounceAll() end
  end
end

function Comms.Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  end
  pendingAnnounceAll = false
  replyTokens, lastReplyAt = {}, {}
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("CHAT_MSG_ADDON")
  frame:RegisterEvent("PLAYER_LOGIN")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", onEvent)
  ns.Lists.OnChange(function(reason, listId)
    if reason == "import" then Comms.Announce(listId) end
  end)
end
