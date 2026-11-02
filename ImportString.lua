local _, ns = ...

local ImportString = {}

ImportString.ERROR_MESSAGES = {
  empty = "Paste an import string first.",
  prefix = "That isn't a BIS List Tooltip import string. Copy it again from the website.",
  version = "This import string needs a newer version of BIS List Tooltip. Update the addon and try again.",
  base64 = "The import string is incomplete or damaged. Copy it again from the website.",
  inflate = "The import string is incomplete or damaged. Copy it again from the website.",
  format = "The import string couldn't be read. Copy it again from the website; if it keeps failing, update the addon.",
}

local BASE64_VALUES = {}
do
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, #alphabet do BASE64_VALUES[alphabet:byte(i)] = i - 1 end
end

-- string.char takes a bounded number of arguments, so output is built in chunks.
local CHUNK_BYTES = 3000

local function decodeBase64(text)
  local length = #text
  if length % 4 ~= 0 then return nil end
  local padding = text:match("=*$")
  if #padding > 2 then return nil end
  local dataLength = length - #padding
  if text:sub(1, dataLength):find("[^A-Za-z0-9+/]") then return nil end

  local chunks, bytes, count = {}, {}, 0
  local function flush()
    chunks[#chunks + 1] = string.char(unpack(bytes, 1, count))
    count = 0
  end
  for i = 1, dataLength, 4 do
    local c1, c2, c3, c4 = text:byte(i, i + 3)
    local n = BASE64_VALUES[c1] * 262144 + BASE64_VALUES[c2] * 4096
      + (c3 and BASE64_VALUES[c3] or 0) * 64 + (c4 and BASE64_VALUES[c4] or 0)
    local remaining = dataLength - i + 1
    bytes[count + 1] = math.floor(n / 65536)
    count = count + 1
    if remaining >= 3 then bytes[count + 1] = math.floor(n / 256) % 256; count = count + 1 end
    if remaining >= 4 then bytes[count + 1] = n % 256; count = count + 1 end
    if count >= CHUNK_BYTES then flush() end
  end
  if count > 0 then flush() end
  return table.concat(chunks)
end

-- Lua 5.1 has no utf8 library, and the client's string functions accept
-- malformed UTF-8, so the body is validated by hand.
local function isValidUtf8(text)
  if not text:find("[\128-\255]") then return true end
  local i, length = 1, #text
  while i <= length do
    local b1 = text:byte(i)
    if b1 < 0x80 then
      i = i + 1
    else
      local continuations, minimum
      if b1 >= 0xC2 and b1 <= 0xDF then continuations, minimum = 1, 0x80
      elseif b1 >= 0xE0 and b1 <= 0xEF then continuations, minimum = 2, 0x800
      elseif b1 >= 0xF0 and b1 <= 0xF4 then continuations, minimum = 3, 0x10000
      else return false end
      if i + continuations > length then return false end
      local codepoint = b1 % (2 ^ (6 - continuations))
      for offset = 1, continuations do
        local continuation = text:byte(i + offset)
        if continuation < 0x80 or continuation > 0xBF then return false end
        codepoint = codepoint * 64 + (continuation - 0x80)
      end
      if codepoint < minimum or codepoint > 0x10FFFF then return false end
      if codepoint >= 0xD800 and codepoint <= 0xDFFF then return false end
      i = i + continuations + 1
    end
  end
  return true
end

-- Plain finds keep empty fields, which gmatch-based splitting would drop.
local function split(text, separator)
  local parts, start = {}, 1
  while true do
    local found = text:find(separator, start, true)
    if not found then
      parts[#parts + 1] = text:sub(start)
      return parts
    end
    parts[#parts + 1] = text:sub(start, found - 1)
    start = found + 1
  end
end

local MAX_BUILD_CHARACTERS = 32

-- The body is already validated UTF-8, so counting non-continuation bytes
-- counts code points.
local function codePointCount(text)
  local _, continuations = text:gsub("[\128-\191]", "")
  return #text - continuations
end

local function toInteger(text, minimum)
  if not text:find("^%d+$") then return nil end
  local value = tonumber(text)
  if value < minimum then return nil end
  return value
end

local function parseHeader(line)
  local fields = split(line, "\t")
  if #fields ~= 7 or fields[1] ~= "H" or fields[5] ~= "forever" then return nil end
  local version = toInteger(fields[3], 1)
  local publishedAt = toInteger(fields[4], 0)
  if not version or not publishedAt then return nil end
  return {
    listId = fields[2], version = version, publishedAt = publishedAt, game = fields[5],
    title = fields[6], author = fields[7], entries = {},
  }
end

function ImportString.Decode(text)
  if type(text) ~= "string" then return nil, "prefix" end
  text = text:gsub("[ \t\r\n]", "")

  local versionDigits = text:match("^BLT(%d+):")
  if not versionDigits then return nil, "prefix" end
  if versionDigits ~= "1" then return nil, "version" end

  local compressed = decodeBase64(text:sub(#"BLT1:" + 1))
  if not compressed then return nil, "base64" end

  local body, unprocessedBytes = LibStub("LibDeflate"):DecompressDeflate(compressed)
  if not body or unprocessedBytes ~= 0 then return nil, "inflate" end

  if not isValidUtf8(body) then return nil, "format" end

  local lines = split(body, "\n")
  local payload = parseHeader(lines[1])
  if not payload then return nil, "format" end

  local classOrder, slotGroups = ns.Catalog.CLASS_ORDER, ns.Catalog.SLOT_GROUPS
  local entries, skipped = payload.entries, 0
  for index = 2, #lines do
    local fields = split(lines[index], "\t")
    if #fields ~= 7 or fields[1] ~= "E" then return nil, "format" end
    local build = fields[3]
    local buildLength = codePointCount(build)
    if buildLength < 1 or buildLength > MAX_BUILD_CHARACTERS or build:find("\r", 1, true) then
      return nil, "format"
    end
    local itemId = toInteger(fields[4], 1)
    local rank = toInteger(fields[6], 1)
    if not itemId or not rank then return nil, "format" end
    if classOrder[fields[2]] and slotGroups[fields[5]] then
      entries[#entries + 1] = {
        classToken = fields[2], build = build, itemId = itemId, slotGroup = fields[5],
        rank = rank, label = fields[7],
      }
    else
      skipped = skipped + 1
    end
  end
  return payload, skipped
end

ns.ImportString = ImportString
