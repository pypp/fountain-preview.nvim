local M = {}

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function is_upper(s)
  if not s:match("%a") then return false end
  return s == s:upper()
end

local function is_character_cue(line)
  if not is_upper(line) then return false end
  local clean = trim(line:gsub("%s*%^%s*$", ""):gsub("%s*%b()%s*$", ""))
  if clean:match("%.$") then return false end
  if not clean:match("%a") then return false end
  return true
end

local function apply_inline(text)
  text = text:gsub("&", "&amp;")
  text = text:gsub("<", "&lt;")
  text = text:gsub(">", "&gt;")
  text = text:gsub("%*%*%*(.-)%*%*%*", "<strong><em>%1</em></strong>")
  text = text:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
  text = text:gsub("%*(.-)%*", "<em>%1</em>")
  text = text:gsub("_(.-)_", "<u>%1</u>")
  return text
end

local function parse_title_page(lines)
  local result = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if trim(line) == "" then break end
    local key, value = line:match("^([%w][%w%s]-):%s*(.-)%s*$")
    if key then
      result[key:lower()] = value
      i = i + 1
      while i <= #lines and lines[i]:match("^%s+") do
        result[key:lower()] = result[key:lower()] .. "\n" .. trim(lines[i])
        i = i + 1
      end
    else
      break
    end
  end
  return result, i
end

M.parse = function(text)
  text = text:gsub("/%*.-%*/", "")
  text = text:gsub("%[%[.-%]%]", "")

  local lines = vim.split(text, "\n")
  local elements = {}
  local start_line = 1

  if #lines > 0 and lines[1]:match("^[%w][%w%s]-:") then
    local td, next_i = parse_title_page(lines)
    if next(td) then
      table.insert(elements, { type = "title_page", data = td, line = 1 })
      start_line = next_i
      while start_line <= #lines and trim(lines[start_line]) == "" do
        start_line = start_line + 1
      end
    end
  end

  -- Collect blocks, tracking the 1-based source line each block starts on
  local blocks = {}
  local block_starts = {}
  local cur = {}
  local cur_start = start_line

  for i = start_line, #lines do
    local line_text = lines[i]
    if trim(line_text) == "" then
      if #cur > 0 then
        table.insert(blocks, cur)
        table.insert(block_starts, cur_start)
        cur = {}
      end
    else
      if #cur == 0 then cur_start = i end
      table.insert(cur, line_text)
    end
  end
  if #cur > 0 then
    table.insert(blocks, cur)
    table.insert(block_starts, cur_start)
  end

  for bi, block in ipairs(blocks) do
    local ln = block_starts[bi]   -- source line of this block
    local first = trim(block[1])
    local upper_first = first:upper()

    if first:match("^=====*$") then
      table.insert(elements, { type = "page_break", line = ln })

    elseif first:match("^=%s") then
      -- skip synopsis

    elseif first:match("^#+%s") then
      local hashes, text = first:match("^(#+)%s+(.*)")
      table.insert(elements, {
        type = "section",
        level = math.min(#hashes, 4),
        text = apply_inline(text),
        line = ln,
      })

    elseif first:match("^>.-<$") then
      local text = first:match("^>%s*(.-)%s*<$")
      if text and text ~= "" then
        table.insert(elements, { type = "centered", text = apply_inline(text), line = ln })
      end

    elseif first:match("^>") then
      local text = trim(first:sub(2))
      table.insert(elements, { type = "transition", text = apply_inline(text), line = ln })

    elseif first:match("^%.[^%.]") then
      table.insert(elements, { type = "scene_heading", text = apply_inline(trim(first:sub(2))), line = ln })

    elseif upper_first:match("^INT[%./]")
        or upper_first:match("^EXT[%./]")
        or upper_first:match("^INT%s*/%s*EXT")
        or upper_first:match("^I/E[%./]")
        or upper_first:match("^EST%.") then
      table.insert(elements, { type = "scene_heading", text = apply_inline(first), line = ln })

    elseif #block == 1 and is_upper(first) and first:match("TO:$") then
      table.insert(elements, { type = "transition", text = apply_inline(first), line = ln })

    elseif #block == 1 and is_upper(first)
        and (first:match("^FADE") or first:match("^SMASH") or first:match("^MATCH CUT")
             or first:match("^CUT TO") or first:match("^DISSOLVE")) then
      table.insert(elements, { type = "transition", text = apply_inline(first), line = ln })

    elseif first:match("^!") then
      local action_lines = {}
      for _, l in ipairs(block) do
        table.insert(action_lines, apply_inline(l:gsub("^!", "")))
      end
      table.insert(elements, { type = "action", lines = action_lines, line = ln })

    elseif first:match("^@") then
      local char = trim(first:sub(2))
      local dual = char:match("%s%^$") ~= nil
      char = trim(char:gsub("%s*%^%s*$", ""))
      table.insert(elements, { type = "character", text = apply_inline(char), dual = dual, line = ln })
      for j = 2, #block do
        local dl = trim(block[j])
        if dl:match("^%(.*%)$") then
          table.insert(elements, { type = "parenthetical", text = apply_inline(dl), line = ln + j - 1 })
        else
          table.insert(elements, { type = "dialogue", text = apply_inline(dl), line = ln + j - 1 })
        end
      end

    elseif #block >= 2 and is_character_cue(first) then
      local char = first
      local dual = char:match("%s%^$") ~= nil
      char = trim(char:gsub("%s*%^%s*$", ""))
      table.insert(elements, { type = "character", text = apply_inline(char), dual = dual, line = ln })
      for j = 2, #block do
        local dl = trim(block[j])
        if dl:match("^%(.*%)$") then
          table.insert(elements, { type = "parenthetical", text = apply_inline(dl), line = ln + j - 1 })
        else
          table.insert(elements, { type = "dialogue", text = apply_inline(dl), line = ln + j - 1 })
        end
      end

    else
      local action_lines = {}
      for _, l in ipairs(block) do
        table.insert(action_lines, apply_inline(l))
      end
      table.insert(elements, { type = "action", lines = action_lines, line = ln })
    end
  end

  return elements
end

-- Helper: data-line attribute string
local function dl(el)
  if el.line then
    return ' data-line="' .. el.line .. '"'
  end
  return ""
end

M.to_html = function(elements)
  local parts = {}

  for _, el in ipairs(elements) do
    if el.type == "title_page" then
      local d = el.data
      local html = '<div class="title-page"' .. dl(el) .. ">"
      if d.title then
        html = html .. '<p class="title">' .. d.title .. "</p>"
      end
      if d.credit then
        html = html .. '<p class="credit">' .. d.credit .. "</p>"
      end
      if d.author or d.authors then
        html = html .. '<p class="author">' .. (d.author or d.authors) .. "</p>"
      end
      if d.source then
        html = html .. '<p class="source">' .. d.source .. "</p>"
      end
      if d["draft date"] then
        html = html .. '<p class="draft-date">' .. d["draft date"] .. "</p>"
      end
      if d.contact then
        html = html .. '<p class="contact">' .. d.contact:gsub("\n", "<br>") .. "</p>"
      end
      html = html .. "</div>"
      table.insert(parts, html)

    elseif el.type == "scene_heading" then
      table.insert(parts, '<h2 class="scene-heading"' .. dl(el) .. ">" .. el.text .. "</h2>")

    elseif el.type == "action" then
      table.insert(parts, '<p class="action"' .. dl(el) .. ">" .. table.concat(el.lines, "<br>") .. "</p>")

    elseif el.type == "character" then
      local cls = el.dual and "character dual" or "character"
      table.insert(parts, '<p class="' .. cls .. '"' .. dl(el) .. ">" .. el.text .. "</p>")

    elseif el.type == "parenthetical" then
      table.insert(parts, '<p class="parenthetical"' .. dl(el) .. ">" .. el.text .. "</p>")

    elseif el.type == "dialogue" then
      table.insert(parts, '<p class="dialogue"' .. dl(el) .. ">" .. el.text .. "</p>")

    elseif el.type == "transition" then
      table.insert(parts, '<p class="transition"' .. dl(el) .. ">" .. el.text .. "</p>")

    elseif el.type == "centered" then
      table.insert(parts, '<p class="centered"' .. dl(el) .. ">" .. el.text .. "</p>")

    elseif el.type == "page_break" then
      table.insert(parts, '<hr class="page-break"' .. dl(el) .. ">")

    elseif el.type == "section" then
      local tag = "h" .. math.min(el.level + 2, 6)
      table.insert(parts, "<" .. tag .. ' class="section"' .. dl(el) .. ">" .. el.text .. "</" .. tag .. ">")
    end
  end

  return table.concat(parts, "\n")
end

return M
