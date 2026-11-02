local wow = require("wow")

local function fixtureText(name)
  local file = assert(io.open(wow.root .. "/tests/fixtures/import-strings/" .. name .. ".txt", "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

-- Comms only accepts CalVer versions, so the tests count publishes on one fixed day.
local function calver(sequence)
  return 20250101000 + sequence
end

local function record(id, sequence, publishedAt)
  return { listId = id, version = calver(sequence), publishedAt = publishedAt or 1761782400, title = id, author = "A", importString = "x" }
end

local function setup(builtins, overrides)
  local ns, stubs = wow.load(overrides)
  ns.BuiltinLists = builtins or {}
  ns.Lists.Init({}, {})
  local offers = {}
  ns.Notices = { Offer = function(listId, version, publishedAt) offers[#offers + 1] = { listId, version, publishedAt } end }
  ns.Comms.Init()
  return ns, stubs, offers
end

local function incoming(stubs, message, sender, channel, prefix)
  stubs.fire("CHAT_MSG_ADDON", prefix or "BISLT", message, channel or "GUILD", sender or "Friend-Realm")
end

local function noErrorsLogged(stubs)
  for _, line in ipairs(stubs.printed) do
    if line:find("OnMessage failed", 1, true) then return false end
  end
  return true
end

local function sentMessages(stubs)
  local messages = {}
  for _, call in ipairs(stubs.sent) do messages[#messages + 1] = call.message end
  return messages
end

return {
  ["announce messages stay under 255 bytes, at most 5"] = function(t)
    local ns = setup()
    local records = {}
    for index = 1, 60 do records[index] = record(string.format("list-number-%03d", index), 100 + index) end
    local messages = ns.Comms.EncodeAnnounce(records)
    t.eq(#messages, 5)
    local seen = 0
    for _, message in ipairs(messages) do
      t.ok(#message <= 255)
      local kind, items = ns.Comms.Parse(message)
      t.eq(kind, "A")
      for _, item in ipairs(items) do
        seen = seen + 1
        t.eq(item.listId, records[seen].listId)
        t.eq(item.version, records[seen].version)
        t.eq(item.publishedAt, records[seen].publishedAt)
      end
    end
    t.eq(seen > 5, true)
  end,

  ["ids that aren't URL-safe or are too long are not sent"] = function(t)
    local ns = setup()
    local messages = ns.Comms.EncodeAnnounce({
      record("has space", 1), record("bad:colon", 1), record(string.rep("a", 33), 1),
      record("ok_id-1", 2), record(string.rep("b", 32), 3),
    })
    t.eq(#messages, 1)
    local _, items = ns.Comms.Parse(messages[1])
    t.eq(#items, 2)
    t.eq(items[1].listId, "ok_id-1")
    t.eq(items[2].listId, string.rep("b", 32))
    t.eq(ns.Comms.EncodeAnnounce({ record("bad id", 1) }), {})
  end,

  ["Parse rejects garbage without raising"] = function(t)
    local ns = setup()
    local garbage = { "", "A1", "A2 x:1:1", "A1 x:1", "A1 x:a:1", "Z1 x:1:1", "A1 " .. string.rep("abcdefgh:1:1761782400 ", 12) .. "z:1:1", "A1 x:1:1  y:2:2",
      "A1 bad id:1:1", "A1 x:1:1 ", "A1 " .. string.rep("a", 33) .. ":1:1" }
    for _, message in ipairs(garbage) do t.eq(ns.Comms.Parse(message), nil) end
    t.eq(ns.Comms.Parse(nil), nil)
    t.eq(ns.Comms.Parse(42), nil)
    local kind, items = ns.Comms.Parse("V1 x:20250101003:99")
    t.eq(kind, "V")
    t.eq(items, { { listId = "x", version = calver(3), publishedAt = 99 } })
  end,

  ["newer version from a guildmate offers a notice"] = function(t)
    local ns, stubs, offers = setup({ record("a", 2) })
    incoming(stubs, "A1 a:20250101003:555 unheld:20250101009:1")
    t.eq(offers, { { "a", calver(3), 555 } })
    incoming(stubs, "V1 a:20250101002:555")
    t.eq(#offers, 1)
    incoming(stubs, "V1 a:20250101004:777")
    t.eq(offers[2], { "a", calver(4), 777 })
  end,

  ["a newer announce works without the notices module"] = function(t)
    local ns, stubs = setup({ record("a", 5) })
    ns.debug = true
    ns.Notices = nil
    incoming(stubs, "V1 a:20250101009:555")
    incoming(stubs, "A1 a:20250101003:555")
    stubs.advance(10)
    t.eq(#stubs.sent, 1)
    t.eq(noErrorsLogged(stubs), true)
  end,

  ["older announce gets one jittered reply"] = function(t)
    local ns, stubs = setup({ record("a", 5) })
    incoming(stubs, "A1 a:20250101003:1")
    t.eq(#stubs.sent, 0)
    stubs.advance(1.5)
    t.eq(#stubs.sent, 0)
    stubs.advance(7)
    t.eq(#stubs.sent, 1)
    t.eq(stubs.sent[1].prefix, "BISLT")
    t.eq(stubs.sent[1].channel, "GUILD")
    t.eq(stubs.sent[1].message, "V1 a:20250101005:1761782400")
  end,

  ["an equal version announce gets no reply"] = function(t)
    local _, stubs = setup({ record("a", 5) })
    incoming(stubs, "A1 a:20250101005:1")
    stubs.advance(10)
    t.eq(#stubs.sent, 0)
  end,

  ["a guildmate's reply cancels ours"] = function(t)
    local _, stubs = setup({ record("a", 5) })
    incoming(stubs, "A1 a:20250101003:1")
    incoming(stubs, "V1 a:20250101005:1", "Other-Realm")
    stubs.advance(10)
    t.eq(#stubs.sent, 0)
  end,

  ["a lower reply does not cancel ours"] = function(t)
    local _, stubs = setup({ record("a", 5) })
    incoming(stubs, "A1 a:20250101003:1")
    incoming(stubs, "V1 a:20250101004:1")
    stubs.advance(10)
    t.eq(#stubs.sent, 1)
  end,

  ["a cancelled reply doesn't fire after a new one is scheduled early"] = function(t)
    local _, stubs = setup({ record("a", 5) })
    local random = math.random
    math.random = function() return 0 end
    incoming(stubs, "A1 a:20250101003:1")
    incoming(stubs, "V1 a:20250101005:1")
    stubs.advance(1)
    math.random = function() return 1 end
    incoming(stubs, "A1 a:20250101003:1")
    math.random = random
    stubs.advance(3)
    t.eq(#stubs.sent, 0)
    stubs.advance(6)
    t.eq(#stubs.sent, 1)
  end,

  ["40 announces in a minute send one reply"] = function(t)
    local _, stubs = setup({ record("a", 5) })
    for _ = 1, 40 do incoming(stubs, "A1 a:20250101003:1") end
    stubs.advance(8)
    t.eq(#stubs.sent, 1)
    for _ = 1, 40 do incoming(stubs, "A1 a:20250101003:1") end
    stubs.advance(8)
    t.eq(#stubs.sent, 1)
    stubs.advance(60)
    incoming(stubs, "A1 a:20250101003:1")
    stubs.advance(8)
    t.eq(#stubs.sent, 2)
  end,

  ["a reply due inside an instance is dropped"] = function(t)
    local _, stubs = setup({ record("a", 5) })
    incoming(stubs, "A1 a:20250101003:1")
    stubs.state.inInstance = true
    stubs.advance(10)
    t.eq(#stubs.sent, 0)
  end,

  ["whispers, other prefixes and our own messages are ignored"] = function(t)
    local _, stubs, offers = setup({ record("a", 5) })
    incoming(stubs, "A1 a:20250101009:1", "Friend-Realm", "WHISPER")
    incoming(stubs, "A1 a:20250101009:1", "Friend-Realm", "GUILD", "OTHER")
    incoming(stubs, "A1 a:20250101009:1", "Tester-Realm")
    incoming(stubs, "A1 a:20250101009:1", "Tester")
    incoming(stubs, "A1 a:20250101001:1", "Tester")
    stubs.advance(10)
    t.eq(offers, {})
    t.eq(#stubs.sent, 0)
  end,

  ["garbage and missing senders never raise"] = function(t)
    local ns, stubs = setup({ record("a", 5) })
    ns.debug = true
    ns.Comms.OnMessage("BISLT", "A1 a:20250101009:1", "GUILD", nil)
    ns.Comms.OnMessage("BISLT", nil, "GUILD", "X")
    ns.Comms.OnMessage(nil, nil, nil, nil)
    incoming(stubs, "\0\1\2")
    incoming(stubs, "A1 a:99999999999999999999999999:1")
    t.eq(noErrorsLogged(stubs), true)
    incoming(stubs, "A1 a:20250101003:1")
    stubs.advance(10)
    t.eq(#stubs.sent, 1)
    t.eq(noErrorsLogged(stubs), true)
  end,

  ["OnMessage failures are logged when debugging"] = function(t)
    local ns, stubs = setup({ record("a", 5) })
    ns.debug = true
    ns.Notices = { Offer = function() error("boom") end }
    incoming(stubs, "A1 a:20250101009:1")
    t.eq(noErrorsLogged(stubs), false)
  end,

  ["reply delay is continuous within 2 to 8 seconds"] = function(t)
    local random = math.random
    for _, fraction in ipairs({ 0, 0.123, 0.999 }) do
      local _, s2 = setup({ record("a", 5) })
      math.random = function() return fraction end
      incoming(s2, "A1 a:20250101003:1")
      math.random = random
      local delay = s2.timers[1].due - s2.now
      t.ok(delay >= 2 and delay <= 8)
      t.ok(math.abs(delay - (2 + fraction * 6)) < 1e-6)
    end
  end,

  ["a newer or equal announce cancels our pending reply"] = function(t)
    local _, stubs = setup({ record("a", 5) })
    incoming(stubs, "A1 a:20250101003:1")
    incoming(stubs, "A1 a:20250101005:1", "Other-Realm")
    stubs.advance(10)
    t.eq(#stubs.sent, 0)
    incoming(stubs, "A1 a:20250101003:1")
    incoming(stubs, "A1 a:20250101007:1", "Other-Realm")
    stubs.advance(10)
    t.eq(#stubs.sent, 0)
  end,

  ["records with unrepresentable numbers are not sent"] = function(t)
    local ns = setup()
    local function raw(id, version, publishedAt)
      return { listId = id, version = version, publishedAt = publishedAt or 1761782400 }
    end
    local messages = ns.Comms.EncodeAnnounce({
      raw("neg", -1), raw("frac", 1.5), raw("big", 1234567890123), raw("badtime", 1, -5),
      raw("hugetime", 1, 1e13), raw("good", 0, 0),
    })
    t.eq(messages, { "A1 good:0:0" })
  end,

  ["announce follow-ups stop when the player enters an instance"] = function(t)
    local records = {}
    for index = 1, 12 do records[index] = record(string.format("list-number-%03d", index), index) end
    local ns, stubs = setup(records)
    ns.Comms.AnnounceAll()
    t.eq(#stubs.sent, 1)
    stubs.state.inInstance = true
    stubs.advance(10)
    t.eq(#stubs.sent, 1)
    stubs.state.inInstance = false
    stubs.fire("PLAYER_ENTERING_WORLD")
    stubs.advance(10)
    t.ok(#stubs.sent > 1)
  end,

  ["no guild means no announce; in an instance the announce waits for leaving"] = function(t)
    local ns, stubs = setup({ record("a", 5), record("b", 6) })
    stubs.state.inGuild = false
    ns.Comms.AnnounceAll()
    ns.Comms.Announce("a")
    stubs.advance(5)
    t.eq(#stubs.sent, 0)
    stubs.fire("PLAYER_ENTERING_WORLD")
    stubs.advance(5)
    t.eq(#stubs.sent, 0)

    stubs.state.inGuild = true
    stubs.state.inInstance = true
    ns.Comms.AnnounceAll()
    ns.Comms.Announce("a")
    stubs.advance(5)
    t.eq(#stubs.sent, 0)
    stubs.fire("PLAYER_ENTERING_WORLD")
    stubs.advance(5)
    t.eq(#stubs.sent, 0)

    stubs.state.inInstance = false
    stubs.fire("PLAYER_ENTERING_WORLD")
    stubs.advance(5)
    t.eq(#stubs.sent, 1)
    stubs.fire("PLAYER_ENTERING_WORLD")
    stubs.advance(5)
    t.eq(#stubs.sent, 1)
  end,

  ["login announce happens 20 s after PLAYER_LOGIN with 1 s spacing"] = function(t)
    local records = {}
    for index = 1, 12 do records[index] = record(string.format("list-number-%03d", index), index) end
    local ns, stubs = setup(records)
    local expected = ns.Comms.EncodeAnnounce(ns.Lists.All())
    t.ok(#expected >= 2)
    stubs.fire("PLAYER_LOGIN")
    stubs.advance(19.5)
    t.eq(#stubs.sent, 0)
    stubs.advance(0.5)
    t.eq(#stubs.sent, 1)
    local firstSentAt = stubs.now
    stubs.advance(0.9)
    t.eq(#stubs.sent, 1)
    stubs.advance(0.1)
    t.eq(#stubs.sent, 2)
    stubs.advance(10)
    t.eq(sentMessages(stubs), expected)
    t.eq(firstSentAt, 1761782400 + 20)
  end,

  ["importing announces that list"] = function(t)
    local ns, stubs = setup()
    local ok = ns.Lists.Import(fixtureText("unknown-class"))
    t.ok(ok)
    t.eq(#stubs.sent, 1)
    t.ok(stubs.sent[1].message:find("^A1 fixtureUnknown01:20251030002:"))
  end,

  ["11-digit CalVer versions are parsed and re-encoded"] = function(t)
    local ns = setup()
    local kind, items = ns.Comms.Parse("A1 abc:20251030001:1761782400")
    t.eq(kind, "A")
    t.eq(items, { { listId = "abc", version = 20251030001, publishedAt = 1761782400 } })
    t.eq(ns.Comms.EncodeAnnounce({ { listId = "abc", version = 20251030001, publishedAt = 1761782400 } }),
      { "A1 abc:20251030001:1761782400" })
  end,

  ["throttled sends and a missing C_ChatInfo don't error"] = function(t)
    local ns, stubs = setup({ record("a", 5) })
    C_ChatInfo.SendAddonMessage = function() return 3 end
    ns.Comms.AnnounceAll()
    stubs.advance(5)

    local ns2, stubs2 = setup({ record("a", 5) }, { C_ChatInfo = false })
    ns2.Comms.AnnounceAll()
    incoming(stubs2, "A1 a:20250101003:1")
    stubs2.advance(10)
    t.eq(#stubs2.sent, 0)
  end,

  ["Init registers the prefix"] = function(t)
    local registered
    local ns, stubs = wow.load()
    C_ChatInfo.RegisterAddonMessagePrefix = function(prefix) registered = prefix; return true end
    ns.Lists.Init({}, {})
    ns.Comms.Init()
    t.eq(registered, "BISLT")
  end,

  ["Parse rejects versions that are not CalVer or lie more than a day ahead"] = function(t)
    local ns = setup()
    -- stubs.now is 2025-10-30 UTC
    t.eq(ns.Comms.Parse("A1 g1:999999999999:0"), nil)
    t.eq(ns.Comms.Parse("A1 g1:5:1761782400"), nil)
    t.eq(ns.Comms.Parse("A1 g1:20251101001:1761782400"), nil)
    t.ok(ns.Comms.Parse("A1 g1:20251031001:1761782400"))
    t.ok(ns.Comms.Parse("A1 g1:20251030001:1761782400"))
  end,

  ["Parse rejects a publishedAt more than a day ahead"] = function(t)
    local ns = setup()
    t.eq(ns.Comms.Parse("A1 g1:20251030001:1761868801"), nil)
    t.eq(ns.Comms.Parse("A1 g1:20251030001:999999999999"), nil)
    t.ok(ns.Comms.Parse("A1 g1:20251030001:1761868800"))
  end,

  ["Parse falls back to time() when GetServerTime is missing"] = function(t)
    local ns = setup(nil, { GetServerTime = false })
    t.eq(ns.Comms.Parse("A1 g1:20251101001:1761782400"), nil)
    t.ok(ns.Comms.Parse("A1 g1:20251031001:1761782400"))
  end,

  ["a spoofed version neither pops up nor silences the real next version"] = function(t)
    local ns, stubs = wow.load()
    ns.BuiltinLists = {}
    BISListTooltipDB = { lists = {}, notified = {}, noticesEnabled = true }
    ns.Lists.Init(BISListTooltipDB, {})
    ns.Lists.Import(require("helpers").encode(table.concat({ "H", "g1", "20251029001", "1761782400", "forever", "Guild", "A" }, "\t")))
    ns.Notices.Init()
    ns.Comms.Init()
    incoming(stubs, "A1 g1:999999999999:0")
    t.eq(#stubs.popups, 0)
    t.eq(BISListTooltipDB.notified, {})
    ns.Notices.Init()
    incoming(stubs, "A1 g1:20251030001:1761782400")
    t.eq(#stubs.popups, 1)
    t.eq(BISListTooltipDB.notified.g1, 20251030001)
  end,
}
