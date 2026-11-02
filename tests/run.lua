-- Usage: lua5.1 tests/run.lua
-- The runner puts tests/ on package.path, so every test file starts with
-- `local wow = require("wow")`; it is the single way tests reach the WoW stubs.
-- A test file returns { ["name"] = function(t) ... end }.

local scriptDir = (arg and arg[0] or "tests/run.lua"):match("^(.*)/[^/]*$") or "."
local root = scriptDir .. "/.."
package.path = scriptDir .. "/?.lua;" .. package.path

local wow = require("wow")
wow.root = root

local write = io.write

local function describe(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = "[" .. describe(k) .. "]=" .. describe(value[k])
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local assertions = {
  eq = function(actual, expected)
    if not deepEqual(actual, expected) then
      error("values differ\n  actual:   " .. describe(actual) .. "\n  expected: " .. describe(expected), 2)
    end
  end,
  ok = function(value, message)
    if not value then error(message or "expected a truthy value", 2) end
  end,
  err = function(fn, pattern)
    local succeeded, message = pcall(fn)
    if succeeded then error("expected an error matching " .. describe(pattern) .. " but none was raised", 2) end
    if not tostring(message):find(pattern) then
      error("error " .. describe(tostring(message)) .. " does not match " .. describe(pattern), 2)
    end
  end,
}

local function listTestFiles()
  local files = {}
  local pipe = io.popen('ls "' .. scriptDir .. '"/*_test.lua 2>/dev/null')
  for line in pipe:lines() do files[#files + 1] = line end
  pipe:close()
  table.sort(files)
  return files
end

local function sortedNames(tests)
  local names = {}
  for name in pairs(tests) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local passed, failed = 0, 0

for _, file in ipairs(listTestFiles()) do
  local chunk, loadError = loadfile(file)
  local tests
  if chunk then
    local ran, result = pcall(chunk)
    tests = ran and result or nil
    if not ran then loadError = result end
  end
  if not tests then
    failed = failed + 1
    write("FAIL " .. file .. " (could not load)\n  " .. tostring(loadError) .. "\n")
  else
    for _, name in ipairs(sortedNames(tests)) do
      local succeeded, message = pcall(tests[name], assertions)
      if succeeded then
        passed = passed + 1
      else
        failed = failed + 1
        write("FAIL " .. file:match("[^/]*$") .. ": " .. name .. "\n  " .. tostring(message) .. "\n")
      end
    end
  end
end

write(string.format("%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
