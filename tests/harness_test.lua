local wow = require("wow")
local decode = require("json")

return {
  ["json decodes surrogate pairs, escapes, numbers, booleans and null"] = function(t)
    t.eq(decode('{"a":[1,-2,true,false,null],"s":"\\u00e9\\ud83d\\ude00\\n"}'),
      { a = { 1, -2, true, false }, s = "\195\169\240\159\152\128\n" })
  end,

  ["json rejects trailing garbage"] = function(t)
    t.err(function() decode("{} x") end, "trailing")
  end,

  ["timers fire only once their delay has elapsed"] = function(t)
    local _, stubs = wow.load()
    local fired = 0
    C_Timer.After(5, function() fired = fired + 1 end)
    stubs.advance(4)
    t.eq(fired, 0)
    stubs.advance(1)
    t.eq(fired, 1)
  end,

  ["fire dispatches only to frames registered for the event"] = function(t)
    local _, stubs = wow.load()
    local seen = {}
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event, ...) seen[#seen + 1] = { event, ... } end)
    stubs.fire("PLAYER_LOGIN", "x")
    stubs.fire("OTHER")
    t.eq(seen, { { "PLAYER_LOGIN", "x" } })
  end,

  ["overrides can remove a global to simulate a missing API"] = function(t)
    wow.load({ TooltipDataProcessor = false })
    t.eq(TooltipDataProcessor, nil)
  end,

  ["globals created in one load do not leak into the next"] = function(t)
    wow.load({ LeakProbe = 1 })
    wow.load()
    t.eq(LeakProbe, nil)
  end,

  ["Ambiguate strips the realm for short names"] = function(t)
    wow.load()
    t.eq(Ambiguate("Bob-Realm", "short"), "Bob")
  end,

  ["timer callbacks see their own due time while advancing"] = function(t)
    local _, stubs = wow.load()
    local start = stubs.now
    local seen = {}
    C_Timer.After(2, function()
      seen[#seen + 1] = GetTime()
      C_Timer.After(1, function() seen[#seen + 1] = GetTime() end)
    end)
    stubs.advance(10)
    t.eq(seen, { start + 2, start + 3 })
    t.eq(GetTime(), start + 10)
  end,
}
