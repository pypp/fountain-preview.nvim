local M = {}

local CSS = [=[
*, *::before, *::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

html {
  scroll-behavior: auto;
}

body {
  background: #1e1e1e;
  padding: 40px 20px 80px;
  min-height: 100vh;
  font-family: 'Courier New', Courier, monospace;
}

#page {
  background: #f9f9f7;
  color: #111111;
  width: 8.5in;
  min-height: 11in;
  margin: 0 auto 40px;
  /* left margin 1.5in, right 1in, top/bottom 1in */
  padding: 1in 1in 1in 1.5in;
  font-size: 12pt;
  line-height: 1.15;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4), 0 12px 40px rgba(0, 0, 0, 0.3);
  border-radius: 2px;
}

/* ── Title page ──────────────────────────────────────── */
.title-page {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 8in;
  text-align: center;
  padding: 1in 0;
  margin-bottom: 1em;
  border-bottom: 1px solid #d0d0d0;
  page-break-after: always;
}

.title-page .title {
  font-size: 14pt;
  font-weight: normal;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  margin-bottom: 2.5em;
}

.title-page .credit {
  margin-top: 0;
  margin-bottom: 0.2em;
}

.title-page .author {
  font-size: 13pt;
  margin-bottom: 0;
}

.title-page .source {
  margin-top: 2em;
  font-style: italic;
}

.title-page .draft-date,
.title-page .contact {
  margin-top: 1.2em;
  font-size: 11pt;
}

/* ── Scene heading ───────────────────────────────────── */
.scene-heading {
  font-size: 12pt;
  font-weight: bold;
  text-transform: uppercase;
  margin: 1.5em 0 0.2em;
  letter-spacing: 0.03em;
  page-break-after: avoid;
}

/* ── Action ──────────────────────────────────────────── */
.action {
  margin: 0 0 1em;
  white-space: pre-wrap;
}

/* ── Character cue ───────────────────────────────────── */
.character {
  /* 2.2in from the 1.5in content-left = 3.7in from page edge (industry standard) */
  margin: 1em 0 0 2.2in;
  text-transform: uppercase;
  white-space: nowrap;
  page-break-after: avoid;
}

/* ── Parenthetical ───────────────────────────────────── */
.parenthetical {
  /* 1.6in from content-left = 3.1in from page edge */
  margin: 0 2.1in 0 1.6in;
  page-break-after: avoid;
}

/* ── Dialogue ────────────────────────────────────────── */
.dialogue {
  /* 1in from content-left, 1.5in from content-right */
  margin: 0 1.5in 1em 1in;
}

/* ── Transition ──────────────────────────────────────── */
.transition {
  text-align: right;
  text-transform: uppercase;
  margin: 1em 0;
  page-break-before: avoid;
}

/* ── Centered text ───────────────────────────────────── */
.centered {
  text-align: center;
  margin: 1em 0;
}

/* ── Page break ──────────────────────────────────────── */
.page-break {
  border: none;
  border-top: 1px dashed #cccccc;
  margin: 2.5em 0;
}

/* ── Section headings (structural, not printed) ──────── */
.section {
  font-family: 'Courier New', Courier, monospace;
  font-size: 10pt;
  color: #666666;
  font-style: italic;
  margin: 2em 0 0.3em;
  padding-left: 0.4em;
  border-left: 3px solid #cccccc;
}

/* ── Connection status pill ──────────────────────────── */
#status {
  position: fixed;
  bottom: 20px;
  right: 20px;
  background: rgba(40, 40, 40, 0.88);
  color: #aaaaaa;
  padding: 5px 14px;
  border-radius: 999px;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  font-size: 11px;
  letter-spacing: 0.04em;
  backdrop-filter: blur(8px);
  border: 1px solid rgba(255, 255, 255, 0.07);
  transition: color 0.4s ease;
  z-index: 9999;
  pointer-events: none;
  user-select: none;
}
]=]

local JS = [=[
(function () {
  var statusEl = document.getElementById('status');
  var screenplayEl = document.getElementById('screenplay');
  var evtSource;

  // Find the element whose data-line is the largest value <= targetLine,
  // then smooth-scroll it into the centre of the viewport.
  function scrollToLine(targetLine) {
    var els = screenplayEl.querySelectorAll('[data-line]');
    var best = null;
    var bestLine = -1;
    for (var i = 0; i < els.length; i++) {
      var elLine = parseInt(els[i].getAttribute('data-line'), 10);
      if (elLine <= targetLine && elLine > bestLine) {
        best = els[i];
        bestLine = elLine;
      }
    }
    if (best) {
      best.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  function connect() {
    evtSource = new EventSource('/events');

    evtSource.onopen = function () {
      statusEl.textContent = '\u25CF Live';
      statusEl.style.color = '#4caf50';
    };

    // Content update (re-render) — also scrolls if a line is provided
    evtSource.addEventListener('update', function (e) {
      try {
        var data = JSON.parse(e.data);
        screenplayEl.innerHTML = data.html;
        if (data.line) {
          scrollToLine(data.line);
        }
      } catch (err) {
        console.error('[fountain-preview] parse error', err);
      }
    });

    // Cursor-move-only scroll (no re-render)
    evtSource.addEventListener('scroll', function (e) {
      var line = parseInt(e.data, 10);
      if (!isNaN(line)) {
        scrollToLine(line);
      }
    });

    evtSource.onerror = function () {
      statusEl.textContent = '\u25CB Reconnecting\u2026';
      statusEl.style.color = '#ff9800';
    };
  }

  connect();
})();
]=]

M.get_page = function(initial_html)
  return table.concat({
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<head>",
    '<meta charset="UTF-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
    "<title>Fountain Preview</title>",
    "<style>",
    CSS,
    "</style>",
    "</head>",
    "<body>",
    '<div id="page">',
    '<div id="screenplay">',
    initial_html,
    "</div>",
    "</div>",
    '<div id="status">&#9675; Connecting&hellip;</div>',
    "<script>",
    JS,
    "</script>",
    "</body>",
    "</html>",
  }, "\n")
end

return M
