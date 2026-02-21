-- Guard against double-loading
if vim.g.loaded_fountain_preview then return end
vim.g.loaded_fountain_preview = true

vim.api.nvim_create_user_command("FountainPreview", function(info)
  local preview = require("fountain_preview")
  local arg = vim.trim(info.args or "")

  if arg == "stop" then
    preview.stop()
  elseif arg == "update" then
    preview.update()
  else
    -- Accept optional port: :FountainPreview 8080
    local port = tonumber(arg)
    preview.start(port and { port = port } or {})
  end
end, {
  nargs = "?",
  desc = "Start/stop Fountain screenplay browser preview",
  complete = function(_, _, _)
    return { "stop", "update" }
  end,
})
