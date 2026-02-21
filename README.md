# nvim-fountain-preview

A Neovim plugin that provides a live HTML preview of [Fountain](https://fountain.io) screenplays in your browser, with real-time updates and synchronized scrolling as you edit.

## Features

- **Live preview** — renders your screenplay in a browser as you type
- **Real-time sync** — browser scrolls to follow your cursor position in the editor
- **Full Fountain support** — title pages, scene headings, action, dialogue, parentheticals, transitions, dual-column dialogue, centered text, sections, page breaks, and inline formatting
- **Auto-opens browser** — optionally launches the browser when preview starts
- **No external dependencies** — pure Lua using Neovim's built-in APIs and libuv

## Requirements

- Neovim 0.7+
- A web browser

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "netanel/nvim-fountain-preview",
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use "netanel/nvim-fountain-preview"
```

## Usage

Open a `.fountain` file and run:

```
:FountainPreview
```

The browser will open at `http://localhost:8765` with a live preview. Edit your screenplay and the preview updates automatically.

### Commands

| Command | Description |
|---|---|
| `:FountainPreview` | Start the preview server |
| `:FountainPreview [port]` | Start on a specific port |
| `:FountainPreview stop` | Stop the preview server |
| `:FountainPreview update` | Force an immediate re-render |

## Configuration

Pass options to `setup()` to override defaults:

```lua
require("fountain_preview").setup({
  port = 8765,           -- Port for the preview server
  auto_open = true,      -- Auto-open browser on start
  debounce_ms = 300,     -- Delay (ms) before re-rendering after edits
  update_events = {      -- Neovim events that trigger a preview update
    "TextChanged",
    "TextChangedI",
    "BufWritePost",
  },
})
```

## Fountain Format Support

| Element | Syntax |
|---|---|
| Scene heading | `INT. LOCATION - DAY` or `.SCENE TEXT` |
| Action | Plain paragraph |
| Character | `CHARACTER NAME` (all caps) |
| Dialogue | Line following a character cue |
| Parenthetical | `(beat)` |
| Transition | `CUT TO:` or uppercase ending in `TO:` |
| Dual dialogue | Append `^` to second character name |
| Centered text | `> TEXT <` |
| Page break | `=====` |
| Section | `# Heading`, `## Sub`, etc. |
| Bold | `**text**` |
| Italic | `*text*` |
| Underline | `_text_` |

## How It Works

1. A lightweight HTTP server starts on the configured port using Neovim's libuv event loop
2. The browser connects and keeps an open [Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) stream
3. On each edit, the Fountain buffer is parsed to HTML and pushed to the browser via SSE
4. Cursor movement sends scroll-only events so the browser viewport stays in sync with the editor

## License

MIT
