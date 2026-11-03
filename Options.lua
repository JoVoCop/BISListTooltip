local _, ns = ...

local Options = {}
ns.Options = Options

local CATEGORY_NAME = "BIS List Tooltip"
local UNAVAILABLE_MESSAGE = "BIS List Tooltip: options are unavailable on this client."
local REMOVE_PROMPT = 'Remove "%s"?\n\nThis removes it for all characters on this account.'
local NOTICES_LABEL = "Tell me when a guildmate has a newer version of one of my lists"
local IMPORT_HINT = "Copy an import string from bislist.io and paste it here."
local NO_LISTS_TEXT = "No lists yet. Import one below."
local OFF_LABEL = "Off (no BIS lines in tooltips)"

local MARGIN = 16
local ROW_HEIGHT = 36
local SECTION_GAP = 18
local IMPORT_WIDTH = 560
local IMPORT_LINES = 6
local IMPORT_LINE_HEIGHT = 14
local ICON_SIZE = 16

local GREEN = { 0.3, 1, 0.3 }
local RED = { 1, 0.3, 0.3 }
local YELLOW = { 1, 0.82, 0 }

local category
local panel
local scroll
local content
local blocks = {}
local rowFrames = {}
local classChecks = {}
local widgets = {}

local function escapePipes(text)
  -- Pipes in a title would otherwise be read as colour/hyperlink escapes.
  return (tostring(text):gsub("|", "||"))
end

local function hasTemplate(name)
  return C_XMLUtil ~= nil and C_XMLUtil.GetTemplateInfo ~= nil and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local function listLabel(record)
  return ("%s (v%s)"):format(escapePipes(record.title), ns.Catalog.FormatVersion(record.version))
end

function Options.SetClassShown(token, shown)
  BISListTooltipCharDB.displayClass[token] = shown == true
end

function Options.SetNoticesEnabled(enabled)
  BISListTooltipDB.noticesEnabled = enabled == true
end

function Options.ConfirmRemove(listId)
  local record = ns.Lists.Get(listId)
  if not record then return end
  StaticPopup_Show("BISLT_CONFIRM_REMOVE", escapePipes(record.title), nil, { listId = listId })
end

local function defineDialogs()
  StaticPopupDialogs.BISLT_CONFIRM_REMOVE = {
    text = REMOVE_PROMPT,
    button1 = "Remove",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(_, data)
      local _, fallbackMessage = ns.Lists.Remove(data.listId)
      if fallbackMessage and widgets.status then
        widgets.status:SetText(fallbackMessage)
        widgets.status:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
      end
      Options.Refresh()
    end,
  }
end

function Options.Import(text)
  local ok, message = ns.Lists.Import(text)
  if widgets.status then
    widgets.status:SetText(message)
    local color = ok and GREEN or RED
    widgets.status:SetTextColor(color[1], color[2], color[3])
  end
  Options.Refresh()
  return ok, message
end

local function addBlock(region, height, gapBefore)
  local block = { region = region, height = height, gap = gapBefore or 0 }
  blocks[#blocks + 1] = block
  return block
end

local function newHeader(text)
  local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  header:SetText(text)
  addBlock(header, 24, SECTION_GAP)
  return header
end

local function newText(text, font)
  local label = content:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
  label:SetJustifyH("LEFT")
  label:SetText(text)
  return label
end

local function newCheckbox(label, onToggle)
  local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
  local text = check.Text
  if not text then
    text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.Text = text
  end
  text:SetText(label)
  check:SetScript("OnClick", function(self) onToggle(self:GetChecked() and true or false) end)
  return check
end

local function buildActiveListControl()
  widgets.emptyText = newText(NO_LISTS_TEXT)

  if hasTemplate("WowStyle1DropdownTemplate") then
    local dropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(320)
    widgets.dropdown = dropdown
    addBlock(dropdown, 28)
  else
    -- Without the dropdown template, a button that cycles through the lists keeps selection possible.
    local cycler = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    cycler:SetSize(320, 24)
    cycler:SetScript("OnClick", function()
      -- Cycles through each list in turn, then Off, then back to the first list.
      local records = ns.Lists.All()
      if #records == 0 then return end
      local active = ns.Lists.GetActive()
      if ns.Lists.IsOff() then
        ns.Lists.SetActive(records[1].listId)
        return
      end
      for index, record in ipairs(records) do
        if active and record.listId == active.listId then
          if records[index + 1] then ns.Lists.SetActive(records[index + 1].listId) else ns.Lists.SetOff() end
          return
        end
      end
      ns.Lists.SetActive(records[1].listId)
    end)
    widgets.cycler = cycler
    addBlock(cycler, 28)
  end
  widgets.emptyBlock = addBlock(widgets.emptyText, 20)
end

local function refreshActiveListControl(records)
  local active = ns.Lists.GetActive()
  local empty = #records == 0
  widgets.emptyText:SetShown(empty)
  widgets.emptyBlock.height = empty and 20 or 0

  if widgets.dropdown then
    widgets.dropdown:SetShown(not empty)
    if widgets.dropdown.SetupMenu then
      widgets.dropdown:SetupMenu(function(_, root)
        for _, record in ipairs(ns.Lists.All()) do
          local listId = record.listId
          root:CreateRadio(listLabel(record), function()
            local current = ns.Lists.GetActive()
            return current ~= nil and current.listId == listId
          end, function() ns.Lists.SetActive(listId) end)
        end
        root:CreateRadio(OFF_LABEL, function() return ns.Lists.IsOff() end, function() ns.Lists.SetOff() end)
      end)
    end
  elseif widgets.cycler then
    widgets.cycler:SetShown(not empty)
    widgets.cycler:SetText(ns.Lists.IsOff() and OFF_LABEL or (active and listLabel(active) or ""))
  end
end

local function buildRow()
  local row = CreateFrame("Frame", nil, content)
  row:SetSize(IMPORT_WIDTH, ROW_HEIGHT)
  row.title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.title:SetJustifyH("LEFT")
  row.title:SetWordWrap(false)
  row.meta = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.remove:SetSize(80, 22)
  row.remove:SetText("Remove")
  row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.remove:SetScript("OnClick", function() Options.ConfirmRemove(row.listId) end)
  return row
end

local function refreshRows(records)
  for index, record in ipairs(records) do
    local row = rowFrames[index]
    if not row then
      row = buildRow()
      rowFrames[index] = row
    end
    row.listId = record.listId
    row.title:SetText(escapePipes(record.title))
    local sourceLabel = record.source == "builtin" and "Built-in" or "Imported"
    row.meta:SetText(("v%s · %s · %s"):format(ns.Catalog.FormatVersion(record.version), date("!%Y-%m-%d", record.publishedAt) or "unknown date", sourceLabel))
    local removable = record.source ~= "builtin"
    row.remove:SetShown(removable)
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.title:SetPoint("RIGHT", removable and row.remove or row, removable and "LEFT" or "RIGHT", -8, 0)
    row:Show()
  end
  for index = #records + 1, #rowFrames do rowFrames[index]:Hide() end
end

local function buildImportSection()
  local editBox
  if hasTemplate("InputScrollFrameTemplate") then
    local scroll = CreateFrame("ScrollFrame", nil, content, "InputScrollFrameTemplate")
    scroll:SetSize(IMPORT_WIDTH, IMPORT_LINES * IMPORT_LINE_HEIGHT + 12)
    if scroll.CharCount then scroll.CharCount:Hide() end
    editBox = scroll.EditBox
    editBox:SetWidth(IMPORT_WIDTH - 20)
    editBox:SetMaxLetters(0)
    addBlock(scroll, IMPORT_LINES * IMPORT_LINE_HEIGHT + 12)
  else
    editBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetSize(IMPORT_WIDTH, IMPORT_LINES * IMPORT_LINE_HEIGHT + 12)
    addBlock(editBox, IMPORT_LINES * IMPORT_LINE_HEIGHT + 12)
  end
  widgets.importBox = editBox

  local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  button:SetSize(100, 24)
  button:SetText("Import")
  button:SetScript("OnClick", function()
    local ok = Options.Import(editBox:GetText())
    if ok then editBox:SetText("") end
  end)
  addBlock(button, 28, 6)

  widgets.status = newText("")
  addBlock(widgets.status, 18, 4)
  addBlock(newText(IMPORT_HINT, "GameFontDisableSmall"), 16, 2)
end

local function classLabel(token)
  local name = ns.Catalog.CLASS_NAMES[token] or token
  if not CreateAtlasMarkup then return name end
  return CreateAtlasMarkup("classicon-" .. token:lower(), ICON_SIZE, ICON_SIZE) .. " " .. name
end

local function buildClassSection()
  for _, token in ipairs(ns.Catalog.CLASS_TOKENS) do
    local check = newCheckbox(classLabel(token), function(checked) Options.SetClassShown(token, checked) end)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if color then check.Text:SetTextColor(color.r, color.g, color.b) end
    classChecks[token] = check
    addBlock(check, 26)
  end
end

local function buildNoticesSection()
  widgets.notices = newCheckbox(NOTICES_LABEL, Options.SetNoticesEnabled)
  addBlock(widgets.notices, 26)
end

local function layout(rowCount)
  local y = MARGIN
  for _, block in ipairs(blocks) do
    y = y + block.gap
    block.region:ClearAllPoints()
    block.region:SetPoint("TOPLEFT", content, "TOPLEFT", MARGIN, -y)
    y = y + block.height
  end
  for index = 1, rowCount do
    local row = rowFrames[index]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", widgets.rowsAnchor, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
  end
  content:SetHeight(y + MARGIN)
end

local function refresh()
  if not panel then return end
  local records = ns.Lists.All()
  refreshActiveListControl(records)
  refreshRows(records)

  for _, block in ipairs(blocks) do
    if block.region == widgets.rowsAnchor then block.height = math.max(#records, 1) * ROW_HEIGHT end
  end
  layout(#records)

  local shown = BISListTooltipCharDB and BISListTooltipCharDB.displayClass or {}
  for token, check in pairs(classChecks) do check:SetChecked(shown[token] == true) end
  widgets.notices:SetChecked(BISListTooltipDB ~= nil and BISListTooltipDB.noticesEnabled == true)
end

Options.Refresh = refresh

local function buildPanel()
  panel = CreateFrame("Frame")
  panel:SetScript("OnShow", function() Options.Refresh() end)

  local template = hasTemplate("ScrollFrameTemplate") and "ScrollFrameTemplate" or nil
  scroll = CreateFrame("ScrollFrame", nil, panel, template)
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(IMPORT_WIDTH + 2 * MARGIN, 1)
  scroll:SetScrollChild(content)
  if not template then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * ROW_HEIGHT)))
    end)
  end

  newHeader("Active list")
  buildActiveListControl()

  newHeader("Your lists")
  widgets.rowsAnchor = CreateFrame("Frame", nil, content)
  widgets.rowsAnchor:SetSize(IMPORT_WIDTH, ROW_HEIGHT)
  addBlock(widgets.rowsAnchor, ROW_HEIGHT)

  newHeader("Import a list")
  buildImportSection()

  newHeader("Show classes")
  buildClassSection()

  newHeader("Guild update notices")
  buildNoticesSection()
end

function Options.Init()
  defineDialogs()
  if not Settings or not Settings.RegisterCanvasLayoutCategory then
    print(UNAVAILABLE_MESSAGE)
    return
  end

  blocks, rowFrames, classChecks, widgets = {}, {}, {}, {}
  buildPanel()
  category = Settings.RegisterCanvasLayoutCategory(panel, CATEGORY_NAME)
  Settings.RegisterAddOnCategory(category)
  ns.Lists.OnChange(refresh)
  refresh()
end

function Options.Open()
  if not category or not Settings or not Settings.OpenToCategory then return end
  Settings.OpenToCategory(category:GetID())
end
