local wow = require("wow")
local decodeJson = require("json")

local FIXTURES = wow.root .. "/tests/fixtures/import-strings/"

local function readFile(path)
  local file, openError = io.open(path, "rb")
  if not file then error("cannot open " .. path .. ": " .. tostring(openError), 0) end
  local text = file:read("*a")
  file:close()
  return text
end

local helpers = require("helpers")
local encode, encodeRaw = helpers.encode, helpers.encodeRaw

local HEADER = "H\tid1\t1\t1761782400\tforever\tTitle\tAuthor"
local ENTRY = "E\tMAGE\tFire\t19019\thead\t1\tBest"

local function fixture(name)
  return readFile(FIXTURES .. name .. ".txt"), decodeJson(readFile(FIXTURES .. name .. ".json"))
end

local function decodeCode(text)
  local ns = wow.load()
  local payload, code = ns.ImportString.Decode(text)
  if payload ~= nil then error("expected failure but decoded", 0) end
  return code
end

return {
  ["decodes every fixture to its JSON"] = function(t)
    local ns = wow.load()
    local expectedSkipped = { basic = 0, unicode = 0, large = 0, ["unknown-class"] = 1 }
    for name, skipped in pairs(expectedSkipped) do
      local text, expected = fixture(name)
      local payload, skippedCount = ns.ImportString.Decode(text)
      t.eq(payload, expected)
      t.eq(skippedCount, skipped)
    end
  end,

  ["ignores spaces, tabs and line breaks anywhere"] = function(t)
    local ns = wow.load()
    local text, expected = fixture("basic")
    text = text:gsub("%s", "")
    local broken = {}
    for i = 1, #text, 40 do broken[#broken + 1] = text:sub(i, i + 39) end
    local payload, skipped = ns.ImportString.Decode("  " .. table.concat(broken, "\r\n") .. "\t\n")
    t.eq(payload, expected)
    t.eq(skipped, 0)
  end,

  ["prefix and version errors"] = function(t)
    local ns = wow.load()
    local function code(text) local _, c = ns.ImportString.Decode(text); return c end
    t.eq(code(""), "prefix")
    t.eq(code("hello"), "prefix")
    t.eq(code("BLT:abc"), "prefix")
    t.eq(code("BLT2:abc"), "version")
    t.eq(code("BLT01:abc"), "version")
    t.eq(code(nil), "prefix")
  end,

  ["NBSP is not stripped"] = function(t)
    local text = fixture("basic"):gsub("%s", "")
    t.eq(decodeCode("BLT1:" .. "\194\160" .. text:sub(6)), "base64")
  end,

  ["base64 errors"] = function(t)
    t.eq(decodeCode("BLT1:abc"), "base64")
    t.eq(decodeCode("BLT1:ab!d"), "base64")
    t.eq(decodeCode("BLT1:a=bc"), "base64")
    t.eq(decodeCode("BLT1:AA=A"), "base64")
    t.eq(decodeCode("BLT1:A==="), "base64")
  end,

  ["inflate errors"] = function(t)
    local text = fixture("basic"):gsub("%s", "")
    local truncated = text:sub(6, 45)
    t.eq(decodeCode("BLT1:" .. truncated), "inflate")
    local deflated = LibStub("LibDeflate"):CompressDeflate(HEADER)
    t.eq(decodeCode(encodeRaw(deflated .. "\1\2\3\4")), "inflate")
  end,

  ["format errors"] = function(t)
    local function body(...) return table.concat({ ... }, "\n") end
    local cases = {
      invalidUtf8 = body("H\tid1\t1\t1761782400\tforever\tTi\255tle\tAuthor"),
      overlong = body("H\tid1\t1\t1761782400\tforever\tT\192\175\tAuthor"),
      surrogate = body("H\tid1\t1\t1761782400\tforever\tT\237\160\128\tAuthor"),
      aboveMax = body("H\tid1\t1\t1761782400\tforever\tT\244\144\128\128\tAuthor"),
      truncatedSequence = body("H\tid1\t1\t1761782400\tforever\tTitle\tAu\226\130"),
      headerSixFields = "H\tid1\t1\t1761782400\tforever\tTitle",
      entryEightFields = body(HEADER, ENTRY .. "\textra"),
      versionZero = "H\tid1\t0\t1761782400\tforever\tTitle\tAuthor",
      rankNegative = body(HEADER, "E\tMAGE\tFire\t19019\thead\t-1\tBest"),
      itemIdFraction = body(HEADER, "E\tMAGE\tFire\t1.5\thead\t1\tBest"),
      gameRetail = "H\tid1\t1\t1761782400\tretail\tTitle\tAuthor",
      secondHeader = body(HEADER, HEADER),
      emptyLine = body(HEADER, ENTRY, "", ENTRY),
      trailingNewline = body(HEADER, ENTRY) .. "\n",
      unknownLineType = body(HEADER, "X\ta\tb"),
      missingHeader = body(ENTRY),
      unknownClassBadRank = body(HEADER, "E\tEVOKER\tDevastation\t19019\thead\tx\tBest"),
      entrySixFields = body(HEADER, "E\tMAGE\t19019\thead\t1\tBest"),
      emptyBuild = body(HEADER, "E\tMAGE\t\t19019\thead\t1\tBest"),
      buildTooLong = body(HEADER, "E\tMAGE\t" .. string.rep("a", 33) .. "\t19019\thead\t1\tBest"),
      buildTooLongSkippedClass = body(HEADER, "E\tEVOKER\t" .. string.rep("a", 33) .. "\t19019\thead\t1\tBest"),
      buildWithCr = body(HEADER, "E\tMAGE\tFi\rre\t19019\thead\t1\tBest"),
      emptyBuildSkippedSlot = body(HEADER, "E\tMAGE\t\t19019\tbogus\t1\tBest"),
      unknownSlotZeroItem = body(HEADER, "E\tMAGE\tFire\t0\tbogus\t1\tBest"),
    }
    for name, text in pairs(cases) do
      local ns = wow.load()
      local payload, code = ns.ImportString.Decode(encode(text))
      t.eq(payload, nil)
      if code ~= "format" then error(name .. ": expected format, got " .. tostring(code), 0) end
    end
  end,

  ["accepts the UTF-8 boundary code points"] = function(t)
    local ns = wow.load()
    local title = "\237\159\191\244\143\191\191"
    local payload = ns.ImportString.Decode(encode("H\tid1\t1\t0\tforever\t" .. title .. "\tAuthor"))
    t.eq(payload.title, title)
  end,

  ["build length counts code points"] = function(t)
    local ns = wow.load()
    local function decodeBuild(build)
      return ns.ImportString.Decode(encode(HEADER .. "\nE\tMAGE\t" .. build .. "\t1\thead\t1\tx"))
    end
    local accepted = string.rep("\226\152\133", 16) .. string.rep("\240\159\146\150", 16)
    local payload = decodeBuild(accepted)
    t.eq(payload.entries[1].build, accepted)
    local _, code = decodeBuild(accepted .. "a")
    t.eq(code, "format")
  end,

  ["build names keep their case and spacing"] = function(t)
    local ns = wow.load()
    local body = HEADER .. "\nE\tMAGE\tFire\t1\thead\t1\tx\nE\tMAGE\tfire \t2\thead\t1\tx"
    local payload = ns.ImportString.Decode(encode(body))
    t.eq(payload.entries[1].build, "Fire")
    t.eq(payload.entries[2].build, "fire ")
  end,

  ["zero entries is valid"] = function(t)
    local ns = wow.load()
    local payload, skipped = ns.ImportString.Decode(encode(HEADER))
    t.eq(payload, {
      listId = "id1", version = 1, publishedAt = 1761782400, game = "forever",
      title = "Title", author = "Author", entries = {},
    })
    t.eq(skipped, 0)
  end,

  ["empty fields are preserved"] = function(t)
    local ns = wow.load()
    local payload = ns.ImportString.Decode(encode("H\tid1\t1\t0\tforever\t\t\n" .. "E\tROGUE\tRogue\t5\thead\t1\t"))
    t.eq(payload.title, "")
    t.eq(payload.author, "")
    t.eq(payload.entries[1].label, "")
  end,

  ["every error code has a user message"] = function(t)
    local ns = wow.load()
    for _, code in ipairs({ "empty", "prefix", "version", "base64", "inflate", "format" }) do
      t.ok(type(ns.ImportString.ERROR_MESSAGES[code]) == "string", code)
    end
  end,

  ["never raises"] = function(t)
    local ns = wow.load()
    math.randomseed(1)
    for _ = 1, 200 do
      local bytes = {}
      for i = 1, math.random(0, 60) do bytes[i] = string.char(math.random(0, 255)) end
      local random = table.concat(bytes)
      for _, text in ipairs({ "BLT1:" .. random, encodeRaw(random) }) do
        local ok, payload, code = pcall(ns.ImportString.Decode, text)
        t.ok(ok, "raised: " .. tostring(payload))
        t.eq(payload, nil)
        t.ok(type(code) == "string")
      end
    end
  end,

  ["large fixture decode time"] = function(t)
    local ns = wow.load()
    local text = fixture("large")
    local start = os.clock()
    ns.ImportString.Decode(text)
    t.ok((os.clock() - start) * 1000 < 500, "large fixture decode took too long")
  end,
}
