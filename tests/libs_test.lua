local wow = require("wow")

local function tocPaths()
  local paths = {}
  for line in io.lines(wow.root .. "/BISListTooltip.toc") do
    if line:match("%S") and not line:match("^##") then
      paths[#paths + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
    end
  end
  return paths
end

local function luaFilesOnDisk()
  local files = {}
  -- Separate commands because find's -maxdepth is global and would hide Data/ and Libs/ files.
  local pipe = io.popen('cd "' .. wow.root .. '" && { ls -1 *.lua 2>/dev/null; find Data Libs -name "*.lua" 2>/dev/null; } | sort')
  for line in pipe:lines() do
    files[#files + 1] = line
  end
  pipe:close()
  return files
end

local function unlistedFiles(files, tocEntries)
  local listed = {}
  for _, path in ipairs(tocEntries) do listed[path] = true end
  local unlisted = {}
  for _, path in ipairs(files) do
    if not listed[path] then unlisted[#unlisted + 1] = path end
  end
  return unlisted
end

return {
  ["LibDeflate registers through LibStub and inflates raw deflate"] = function(t)
    wow.load()
    local LibDeflate = LibStub("LibDeflate")
    t.ok(LibDeflate, "LibDeflate via LibStub")
    local packed = LibDeflate:CompressDeflate("hello hello hello")
    t.eq(LibDeflate:DecompressDeflate(packed), "hello hello hello")
  end,

  ["the TOC lists every addon Lua file and nothing missing"] = function(t)
    local entries = tocPaths()
    for _, path in ipairs(entries) do
      local handle = io.open(wow.root .. "/" .. path, "r")
      t.ok(handle, "TOC entry exists on disk: " .. path)
      if handle then handle:close() end
    end
    t.eq(unlistedFiles(luaFilesOnDisk(), entries), {})
  end,

  ["the disk scan reaches Libs/ files"] = function(t)
    local found = {}
    for _, path in ipairs(luaFilesOnDisk()) do found[path] = true end
    t.ok(found["Libs/LibStub/LibStub.lua"], "Libs/LibStub/LibStub.lua enumerated")
    t.ok(found["Libs/LibDeflate/LibDeflate.lua"], "Libs/LibDeflate/LibDeflate.lua enumerated")
  end,

  ["the completeness check reports unlisted files"] = function(t)
    t.eq(unlistedFiles({ "Data/Extra.lua", "Core.lua" }, { "Core.lua" }), { "Data/Extra.lua" })
  end,

  ["each load gets a fresh LibStub registry"] = function(t)
    wow.load()
    local first = LibStub("LibDeflate")
    wow.load()
    t.ok(LibStub("LibDeflate") ~= first, "second load re-registers the library")
  end,
}
