-- Test-only encoder, the inverse of ImportString.Decode.

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64Encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local chars = {}
    for shift = 3, 0, -1 do
      local index = math.floor(n / 64 ^ shift) % 64
      chars[#chars + 1] = ALPHABET:sub(index + 1, index + 1)
    end
    if not b then chars[3] = "="; chars[4] = "=" elseif not c then chars[4] = "=" end
    out[#out + 1] = table.concat(chars)
  end
  return table.concat(out)
end

-- The prefix defaults to BLT1; BLT2 strings pass it explicitly.
local function encodeRaw(bytes, prefix)
  return (prefix or "BLT1") .. ":" .. base64Encode(bytes)
end

local function encode(body, prefix)
  return encodeRaw(LibStub("LibDeflate"):CompressDeflate(body), prefix)
end

return { base64Encode = base64Encode, encodeRaw = encodeRaw, encode = encode }
