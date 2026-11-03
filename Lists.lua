local _, ns = ...

local Lists = {}
ns.Lists = Lists

local db, charDB
local listeners = {}
local indexCache = { key = nil, index = nil }

local function reportListenerError(message)
  if geterrorhandler then return geterrorhandler()(message) end
  print("BIS List Tooltip: " .. tostring(message))
end

-- A throwing listener must not abort the import/remove that triggered it or starve later listeners.
local function notify(reason, listId)
  for _, listener in ipairs(listeners) do
    xpcall(function() listener(reason, listId) end, reportListenerError)
  end
end

-- Titles are author-written and these messages are printed to chat, where "|" starts an escape sequence.
local function escapePipes(text)
  return (tostring(text):gsub("|", "||"))
end

local function withSource(record, source)
  local copy = {}
  for key, value in pairs(record) do copy[key] = value end
  copy.source = source
  return copy
end

local function builtinById(listId)
  for _, record in ipairs(ns.BuiltinLists or {}) do
    if record.listId == listId then return record end
  end
end

local function resolve(listId)
  local builtinRecord = builtinById(listId)
  local importedRecord = db.lists[listId]
  if importedRecord and (not builtinRecord or importedRecord.version > builtinRecord.version) then
    return withSource(importedRecord, "imported")
  end
  if builtinRecord then return withSource(builtinRecord, "builtin") end
end

function Lists.Init(savedDb, savedCharDb)
  db, charDB = savedDb, savedCharDb
  db.lists = db.lists or {}
  indexCache = { key = nil, index = nil }
end

function Lists.All()
  local result, seen = {}, {}
  for _, record in ipairs(ns.BuiltinLists or {}) do
    if not seen[record.listId] then
      seen[record.listId] = true
      result[#result + 1] = resolve(record.listId)
    end
  end
  local imported = {}
  for listId in pairs(db.lists) do
    if not seen[listId] then imported[#imported + 1] = resolve(listId) end
  end
  table.sort(imported, function(a, b)
    local titleA, titleB = (a.title or ""):lower(), (b.title or ""):lower()
    if titleA ~= titleB then return titleA < titleB end
    return a.listId < b.listId
  end)
  for _, record in ipairs(imported) do result[#result + 1] = record end
  return result
end

function Lists.Get(listId)
  if listId == nil then return nil end
  return resolve(listId)
end

function Lists.HeldVersion(listId)
  local record = Lists.Get(listId)
  return record and record.version or nil
end

function Lists.OnChange(listener)
  listeners[#listeners + 1] = listener
end

-- Choosing a list, by hand or by importing a new one, also turns BIS lines back on.
local function setActiveQuietly(record)
  charDB.activeListId = record.listId
  charDB.activeListTitle = record.title
  charDB.off = nil
end

function Lists.SetActive(listId)
  local record = Lists.Get(listId)
  if not record then return end
  setActiveQuietly(record)
  notify("active", listId)
end

-- Hides BIS lines on this character; the chosen list is kept so picking it again is one click.
function Lists.SetOff()
  charDB.off = true
  notify("active", nil)
end

function Lists.IsOff()
  return charDB.off == true
end

function Lists.GetActive()
  if charDB.off then return nil end
  return Lists.Get(charDB.activeListId)
end

function Lists.Import(text)
  local messages = ns.ImportString.ERROR_MESSAGES
  if type(text) ~= "string" or not text:find("%S") then return false, messages.empty end

  local payload, skippedOrCode = ns.ImportString.Decode(text)
  if not payload then return false, messages[skippedOrCode] end

  local held = Lists.HeldVersion(payload.listId)
  if held and held == payload.version then
    return false, ('You already have version %s of "%s".'):format(ns.Catalog.FormatVersion(held), escapePipes(payload.title))
  elseif held and held > payload.version then
    return false, ('You already have a newer version (%s) of "%s".'):format(ns.Catalog.FormatVersion(held), escapePipes(payload.title))
  end

  db.lists[payload.listId] = {
    listId = payload.listId,
    version = payload.version,
    publishedAt = payload.publishedAt,
    title = payload.title,
    author = payload.author,
    importString = (text:gsub("[ \t\r\n]", "")),
  }

  local message = ('Imported "%s" (version %s).'):format(escapePipes(payload.title), ns.Catalog.FormatVersion(payload.version))
  if not held then
    setActiveQuietly(Lists.Get(payload.listId))
    message = message .. " It is now your active list."
  elseif charDB.activeListId == payload.listId then
    charDB.activeListTitle = payload.title
  end
  if skippedOrCode > 0 then
    message = message .. (" %d entries were skipped because this version of the addon doesn't know their class or slot. Update the addon to see them."):format(skippedOrCode)
  end
  notify("import", payload.listId)
  return true, message
end

-- The list bislist.io marks as the default, so a new character starts on the list we recommend rather than whichever sorts first.
local function startingList()
  for _, record in ipairs(ns.BuiltinLists or {}) do
    if record.isDefault then return Lists.Get(record.listId) end
  end
  return Lists.All()[1]
end

-- Falls back to the starting list; returns the chat/status message naming what was lost and what is used now.
local function fallBackFrom(removedTitle)
  local first = startingList()
  if first then
    setActiveQuietly(first)
    return ('"%s" was removed, so BIS List Tooltip is now using "%s".'):format(escapePipes(removedTitle), escapePipes(first.title))
  end
  charDB.activeListId, charDB.activeListTitle = nil, nil
  return ('"%s" was removed, so no list is active.'):format(escapePipes(removedTitle))
end

function Lists.Remove(listId)
  local record = db.lists[listId]
  if not record then return false end
  db.lists[listId] = nil
  notify("remove", listId)
  if charDB.activeListId ~= listId or Lists.Get(listId) then return true end

  local message = fallBackFrom(record.title or listId)
  local active = charDB.activeListId
  notify("active", active)
  return true, message
end

function Lists.EnsureActive()
  if charDB.off then return nil end
  local activeId = charDB.activeListId
  if activeId and Lists.Get(activeId) then return nil end
  if not activeId then
    local first = startingList()
    if first then setActiveQuietly(first) end
    return nil
  end
  return fallBackFrom(charDB.activeListTitle or activeId)
end

function Lists.BuildIndex(payload)
  local classOrder = ns.Catalog.CLASS_ORDER
  local slotOrder = {}
  for position, id in ipairs(ns.Catalog.SLOT_GROUP_ORDER) do slotOrder[id] = position end
  local totals, buildPosition, buildCount = {}, {}, 0
  for _, entry in ipairs(payload.entries) do
    local buildKey = entry.classToken .. "\0" .. entry.build:lower()
    if not buildPosition[buildKey] then
      buildCount = buildCount + 1
      buildPosition[buildKey] = buildCount
    end
    local key = buildKey .. "\0" .. entry.slotGroup
    totals[key] = (totals[key] or 0) + 1
  end

  local index = {}
  for _, entry in ipairs(payload.entries) do
    local forItem = index[entry.itemId]
    if not forItem then
      forItem = {}
      index[entry.itemId] = forItem
    end
    local buildKey = entry.classToken .. "\0" .. entry.build:lower()
    forItem[#forItem + 1] = {
      classToken = entry.classToken,
      build = entry.build,
      label = entry.label,
      rank = entry.rank,
      total = totals[buildKey .. "\0" .. entry.slotGroup],
      slotGroup = entry.slotGroup,
      buildPosition = buildPosition[buildKey],
    }
  end

  -- table.sort is unstable, so the slot group is the final tie-break to keep tooltip order deterministic.
  for _, forItem in pairs(index) do
    table.sort(forItem, function(a, b)
      if a.classToken ~= b.classToken then return (classOrder[a.classToken] or math.huge) < (classOrder[b.classToken] or math.huge) end
      if a.buildPosition ~= b.buildPosition then return a.buildPosition < b.buildPosition end
      if a.rank ~= b.rank then return a.rank < b.rank end
      if a.label ~= b.label then return a.label < b.label end
      return (slotOrder[a.slotGroup] or math.huge) < (slotOrder[b.slotGroup] or math.huge)
    end)
  end
  return index
end

function Lists.GetActiveIndex(activeRecord)
  local record = activeRecord or Lists.GetActive()
  if not record then return nil end

  local key = record.listId .. ":" .. record.version
  if indexCache.key == key then return indexCache.index or nil end

  local payload = ns.ImportString.Decode(record.importString)
  -- false marks a failed decode so a broken record isn't re-decoded on every hover.
  indexCache = { key = key, index = payload and Lists.BuildIndex(payload) or false }
  return indexCache.index or nil
end
