local _, ns = ...

local Notices = {}
ns.Notices = Notices

local RETRY_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

local pending = {}
local shownThisSession = {}
local popupShowing = false

local function findEditBox(dialog)
  if dialog.GetEditBox then return dialog:GetEditBox() end
  return dialog.editBox or dialog.EditBox
end

local function showUrl(dialog, data)
  local editBox = findEditBox(dialog)
  if not editBox then return end
  if editBox.SetText then editBox:SetText(data.url) end
  if editBox.HighlightText then editBox:HighlightText() end
  if editBox.SetFocus then editBox:SetFocus() end
end

-- Deferred because Blizzard's StaticPopup_OnHide keeps tearing the frame down
-- after this callback; showing synchronously could reuse and clobber it.
local function onHide()
  popupShowing = false
  C_Timer.After(0, Notices.TryShow)
end

local function defineDialogs()
  local common = {
    text = "%s",
    button1 = OKAY or "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnHide = onHide,
  }
  local imported, builtin = {}, {}
  for key, value in pairs(common) do
    imported[key] = value
    builtin[key] = value
  end
  imported.hasEditBox = true
  imported.OnShow = showUrl
  StaticPopupDialogs.BISLT_NEWER_IMPORTED = imported
  StaticPopupDialogs.BISLT_NEWER_BUILTIN = builtin
end

local function formatMessage(record, version, publishedAt)
  -- Pipes in a title would otherwise be read as colour/hyperlink escapes.
  local title = tostring(record.title or record.listId):gsub("|", "||")
  local published = date("!%Y-%m-%d", publishedAt) or "an unknown date"
  if record.source == "builtin" then
    return string.format('A newer version of the built-in list "%s" is out: version %s, published %s.\n\nUpdate BIS List Tooltip through CurseForge to get it.', title, ns.Catalog.FormatVersion(version), published)
  end
  return string.format('A newer version of "%s" is available: version %s, published %s.\n\nCopy the link, open it in your browser and import the new version.', title, ns.Catalog.FormatVersion(version), published)
end

-- Drops entries that can never show; returns the entries that still could.
local function candidates()
  local list = {}
  for listId, offer in pairs(pending) do
    local record = ns.Lists.Get(listId)
    local held = ns.Lists.HeldVersion(listId) or 0
    local notified = BISListTooltipDB.notified[listId] or 0
    if not record or offer.version <= held or offer.version <= notified then
      pending[listId] = nil
    elseif not shownThisSession[listId] then
      list[#list + 1] = { listId = listId, offer = offer, record = record }
    end
  end
  table.sort(list, function(a, b)
    local titleA, titleB = tostring(a.record.title or a.listId), tostring(b.record.title or b.listId)
    if titleA ~= titleB then return titleA < titleB end
    return a.listId < b.listId
  end)
  return list
end

function Notices.Offer(listId, version, publishedAt)
  if not ns.Lists.Get(listId) then return end
  local existing = pending[listId]
  if not existing or version > existing.version then
    pending[listId] = { version = version, publishedAt = publishedAt }
  end
  Notices.TryShow()
end

function Notices.TryShow()
  if popupShowing then return end
  if not BISListTooltipDB.noticesEnabled then return end
  if InCombatLockdown() then return end
  if IsInInstance() then return end

  local chosen = candidates()[1]
  if not chosen then return end

  local which = chosen.record.source == "builtin" and "BISLT_NEWER_BUILTIN" or "BISLT_NEWER_IMPORTED"
  local data = { listId = chosen.listId, url = ns.SITE_URL .. "/lists/" .. chosen.listId }
  local formatted, message = pcall(formatMessage, chosen.record, chosen.offer.version, chosen.offer.publishedAt)
  if not formatted then
    -- Left pending, an offer that can never be formatted would raise on every retry event.
    pending[chosen.listId] = nil
    if geterrorhandler then geterrorhandler()(message) else print("BIS List Tooltip: " .. tostring(message)) end
    return
  end

  popupShowing = true
  if not StaticPopup_Show(which, message, nil, data) then
    popupShowing = false
    return
  end
  BISListTooltipDB.notified[chosen.listId] = chosen.offer.version
  pending[chosen.listId] = nil
  shownThisSession[chosen.listId] = true
end

function Notices.Init()
  pending = {}
  shownThisSession = {}
  popupShowing = false
  defineDialogs()

  local frame = CreateFrame("Frame")
  for _, event in ipairs(RETRY_EVENTS) do frame:RegisterEvent(event) end
  frame:SetScript("OnEvent", function() Notices.TryShow() end)
end
