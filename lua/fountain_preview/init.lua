local M = {}

local parser = require("fountain_preview.parser")
local server = require("fountain_preview.server")

local uv = vim.uv or vim.loop

M.config = {
  port = 8765,
  auto_open = true,
  -- Events that trigger a preview update
  update_events = { "TextChanged", "TextChangedI", "BufWritePost" },
  -- Milliseconds to wait after the last edit before re-rendering
  debounce_ms = 300,
}

local _timer = nil
local _scroll_timer = nil
local _augroup = nil

local function get_html(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  local ok, result = pcall(function()
    return parser.to_html(parser.parse(text))
  end)
  if ok then
    return result
  else
    vim.notify("fountain-preview: parse error: " .. tostring(result), vim.log.levels.WARN)
    return "<p style='color:red'>Parse error — check Neovim messages.</p>"
  end
end

local function schedule_update(bufnr)
  if _timer then
    pcall(function()
      _timer:stop()
      _timer:close()
    end)
    _timer = nil
  end

  _timer = uv.new_timer()
  _timer:start(
    M.config.debounce_ms,
    0,
    vim.schedule_wrap(function()
      if _timer then
        pcall(function()
          _timer:stop()
          _timer:close()
        end)
        _timer = nil
      end
      -- Buffer might have been wiped by the time the timer fires
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      local line = vim.api.nvim_win_get_cursor(0)[1]
      server.broadcast(get_html(bufnr), line)
    end)
  )
end

local function schedule_scroll()
  if _scroll_timer then
    pcall(function()
      _scroll_timer:stop()
      _scroll_timer:close()
    end)
    _scroll_timer = nil
  end
  _scroll_timer = uv.new_timer()
  _scroll_timer:start(80, 0, vim.schedule_wrap(function()
    if _scroll_timer then
      pcall(function()
        _scroll_timer:stop()
        _scroll_timer:close()
      end)
      _scroll_timer = nil
    end
    local line = vim.api.nvim_win_get_cursor(0)[1]
    server.send_scroll(line)
  end))
end

local function open_browser(url)
  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = { "open", url }
  elseif vim.fn.has("win32") == 1 then
    cmd = { "cmd", "/c", "start", url }
  else
    cmd = { "xdg-open", url }
  end
  vim.fn.jobstart(cmd, { detach = true })
end

-- Public API ──────────────────────────────────────────────────────────────────

-- Start the preview server for the current buffer.
-- opts table (optional) overrides M.config keys.
M.start = function(opts)
  opts = opts or {}
  M.config = vim.tbl_extend("force", M.config, opts)

  local bufnr = vim.api.nvim_get_current_buf()

  if not server.start(M.config.port) then return end

  -- Render the current buffer immediately
  server.broadcast(get_html(bufnr))

  -- Autocommands for live updates
  _augroup = vim.api.nvim_create_augroup("FountainPreview", { clear = true })

  for _, event in ipairs(M.config.update_events) do
    vim.api.nvim_create_autocmd(event, {
      group = _augroup,
      buffer = bufnr,
      callback = function()
        schedule_update(bufnr)
      end,
    })
  end

  -- Scroll browser to follow cursor
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = _augroup,
    buffer = bufnr,
    callback = function()
      schedule_scroll()
    end,
  })

  -- Clean up when the buffer is unloaded
  vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
    group = _augroup,
    buffer = bufnr,
    once = true,
    callback = function()
      M.stop()
    end,
  })

  local url = "http://localhost:" .. M.config.port

  if M.config.auto_open then
    open_browser(url)
  end

  vim.notify("fountain-preview: live at " .. url, vim.log.levels.INFO)
end

-- Stop the server and remove autocommands.
M.stop = function()
  if _timer then
    pcall(function()
      _timer:stop()
      _timer:close()
    end)
    _timer = nil
  end
  if _scroll_timer then
    pcall(function()
      _scroll_timer:stop()
      _scroll_timer:close()
    end)
    _scroll_timer = nil
  end

  server.stop()

  if _augroup then
    pcall(vim.api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end

  vim.notify("fountain-preview: stopped", vim.log.levels.INFO)
end

-- Force an immediate re-render of the current buffer.
M.update = function()
  local bufnr = vim.api.nvim_get_current_buf()
  server.broadcast(get_html(bufnr))
end

return M
