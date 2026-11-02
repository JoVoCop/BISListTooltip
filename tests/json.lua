-- Fixture-only JSON decoder; not meant for untrusted input.

local function utf8Encode(codepoint)
  if codepoint < 0x80 then
    return string.char(codepoint)
  elseif codepoint < 0x800 then
    return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
  elseif codepoint < 0x10000 then
    return string.char(0xE0 + math.floor(codepoint / 0x1000),
      0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
  end
  return string.char(0xF0 + math.floor(codepoint / 0x40000),
    0x80 + math.floor(codepoint / 0x1000) % 0x40,
    0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
end

local SIMPLE_ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function decode(text)
  local pos = 1

  local function fail(message)
    error(string.format("json: %s at position %d", message, pos), 0)
  end

  local function skipWhitespace()
    pos = text:find("[^ \t\r\n]", pos) or #text + 1
  end

  local parseValue

  local function parseHex4()
    local hex = text:match("^%x%x%x%x", pos)
    if not hex then fail("bad \\u escape") end
    pos = pos + 4
    return tonumber(hex, 16)
  end

  local function parseString()
    pos = pos + 1
    local parts = {}
    while true do
      local stop = text:find('["\\]', pos)
      if not stop then fail("unterminated string") end
      parts[#parts + 1] = text:sub(pos, stop - 1)
      pos = stop + 1
      if text:sub(stop, stop) == '"' then break end
      local escape = text:sub(pos, pos)
      pos = pos + 1
      if escape == "u" then
        local codepoint = parseHex4()
        if codepoint >= 0xD800 and codepoint <= 0xDBFF then
          if text:sub(pos, pos + 1) ~= "\\u" then fail("lone high surrogate") end
          pos = pos + 2
          local low = parseHex4()
          if low < 0xDC00 or low > 0xDFFF then fail("bad low surrogate") end
          codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
        end
        parts[#parts + 1] = utf8Encode(codepoint)
      elseif SIMPLE_ESCAPES[escape] then
        parts[#parts + 1] = SIMPLE_ESCAPES[escape]
      else
        fail("bad escape")
      end
    end
    return table.concat(parts)
  end

  local function parseNumber()
    local literal = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if not literal or literal == "" then fail("bad number") end
    pos = pos + #literal
    return tonumber(literal)
  end

  local function parseArray()
    pos = pos + 1
    local array = {}
    skipWhitespace()
    if text:sub(pos, pos) == "]" then pos = pos + 1; return array end
    while true do
      array[#array + 1] = parseValue()
      skipWhitespace()
      local separator = text:sub(pos, pos)
      pos = pos + 1
      if separator == "]" then return array end
      if separator ~= "," then fail("expected , or ]") end
    end
  end

  local function parseObject()
    pos = pos + 1
    local object = {}
    skipWhitespace()
    if text:sub(pos, pos) == "}" then pos = pos + 1; return object end
    while true do
      skipWhitespace()
      if text:sub(pos, pos) ~= '"' then fail("expected string key") end
      local key = parseString()
      skipWhitespace()
      if text:sub(pos, pos) ~= ":" then fail("expected :") end
      pos = pos + 1
      object[key] = parseValue()
      skipWhitespace()
      local separator = text:sub(pos, pos)
      pos = pos + 1
      if separator == "}" then return object end
      if separator ~= "," then fail("expected , or }") end
    end
  end

  local LITERALS = { ["true"] = true, ["false"] = false }

  -- JSON null decodes to nil, so keys holding null are simply absent.
  function parseValue()
    skipWhitespace()
    local char = text:sub(pos, pos)
    if char == "{" then return parseObject() end
    if char == "[" then return parseArray() end
    if char == '"' then return parseString() end
    for literal, value in pairs(LITERALS) do
      if text:sub(pos, pos + #literal - 1) == literal then
        pos = pos + #literal
        return value
      end
    end
    if text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
    return parseNumber()
  end

  local value = parseValue()
  skipWhitespace()
  if pos <= #text then fail("trailing characters") end
  return value
end

return decode
