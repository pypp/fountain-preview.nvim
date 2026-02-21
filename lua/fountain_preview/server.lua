local M = {}

local uv = vim.uv or vim.loop

M.port = 8765
M.current_html = ""
M._server = nil
M._sse_clients = {}

local function close_handle(h)
  if h and not h:is_closing() then
    pcall(function() h:close() end)
  end
end

local function remove_sse_client(client)
  for i, c in ipairs(M._sse_clients) do
    if c == client then
      table.remove(M._sse_clients, i)
      return
    end
  end
end

local function send_response(client, status, content_type, body)
  local header = string.format(
    "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
    status, content_type, #body
  )
  pcall(function()
    client:write(header .. body, function()
      close_handle(client)
    end)
  end)
end

local function handle_request(client, buf)
  local method, path = buf:match("^(%u+)%s+([^%s]+)%s+HTTP")
  if not method then
    close_handle(client)
    return
  end

  if path == "/" then
    local template = require("fountain_preview.template")
    local page = template.get_page(M.current_html)
    send_response(client, "200 OK", "text/html; charset=utf-8", page)

  elseif path == "/events" then
    -- Open SSE stream
    local headers = table.concat({
      "HTTP/1.1 200 OK\r\n",
      "Content-Type: text/event-stream\r\n",
      "Cache-Control: no-cache\r\n",
      "Connection: keep-alive\r\n",
      "X-Accel-Buffering: no\r\n",
      "\r\n",
    })
    pcall(function() client:write(headers) end)

    -- Send the current content immediately so the page populates on connect
    local encoded = vim.json.encode({ html = M.current_html })
    pcall(function() client:write("event: update\ndata: " .. encoded .. "\n\n") end)

    table.insert(M._sse_clients, client)

  else
    send_response(client, "404 Not Found", "text/plain", "Not found")
  end
end

local function write_to_clients(msg)
  local dead = {}
  for i, client in ipairs(M._sse_clients) do
    if client:is_closing() then
      table.insert(dead, i)
    else
      pcall(function()
        client:write(msg, function(err)
          if err then remove_sse_client(client) end
        end)
      end)
    end
  end
  for i = #dead, 1, -1 do
    table.remove(M._sse_clients, dead[i])
  end
end

-- Broadcast updated HTML (and optional cursor line) to all SSE clients
M.broadcast = function(html, line)
  M.current_html = html
  if #M._sse_clients == 0 then return end
  local payload = { html = html }
  if line then payload.line = line end
  local msg = "event: update\ndata: " .. vim.json.encode(payload) .. "\n\n"
  write_to_clients(msg)
end

-- Send a scroll-only event (no HTML update)
M.send_scroll = function(line)
  if #M._sse_clients == 0 then return end
  write_to_clients("event: scroll\ndata: " .. tostring(line) .. "\n\n")
end

M.start = function(port)
  if M._server then return true end
  M.port = port or 8765

  local ok, server = pcall(function() return uv.new_tcp() end)
  if not ok or not server then
    vim.notify("fountain-preview: failed to create TCP socket", vim.log.levels.ERROR)
    return false
  end

  local bind_ok, bind_err = pcall(function()
    server:bind("127.0.0.1", M.port)
  end)
  if not bind_ok then
    vim.notify("fountain-preview: cannot bind to port " .. M.port .. ": " .. tostring(bind_err), vim.log.levels.ERROR)
    close_handle(server)
    return false
  end

  local listen_ok, listen_err = pcall(function()
    server:listen(128, function(err)
      if err then return end

      local client = uv.new_tcp()
      if not pcall(function() server:accept(client) end) then
        close_handle(client)
        return
      end

      local buf = ""
      local handled = false

      client:read_start(function(read_err, chunk)
        if read_err or not chunk then
          remove_sse_client(client)
          close_handle(client)
          return
        end

        buf = buf .. chunk
        -- Wait for the end of the HTTP request headers
        if not handled and buf:find("\r\n\r\n") then
          handled = true
          vim.schedule(function()
            handle_request(client, buf)
          end)
        end
      end)
    end)
  end)

  if not listen_ok then
    vim.notify("fountain-preview: cannot listen on port " .. M.port .. ": " .. tostring(listen_err), vim.log.levels.ERROR)
    close_handle(server)
    return false
  end

  M._server = server
  return true
end

M.stop = function()
  for _, client in ipairs(M._sse_clients) do
    close_handle(client)
  end
  M._sse_clients = {}

  if M._server then
    close_handle(M._server)
    M._server = nil
  end
end

return M
