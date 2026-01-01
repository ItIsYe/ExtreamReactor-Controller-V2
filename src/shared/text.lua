local M = {}

local replacements = {
  ["ä"] = "ae", ["ö"] = "oe", ["ü"] = "ue",
  ["Ä"] = "Ae", ["Ö"] = "Oe", ["Ü"] = "Ue",
  ["ß"] = "ss",
}

local function sanitizeText(text)
  local s = tostring(text or "")
  s = s:gsub("[äöüÄÖÜß]", replacements)
  s = s:gsub("[^%z\1-\127]", "?")
  return s
end

M.sanitizeText = sanitizeText

return M
