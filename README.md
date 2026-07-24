# ClaudeSnap

I basically wanted a way to have my screenshots and texts (that i copy/paste) automatically be sent to the last current claude chat open. This way, I am saving time by being able to have it do exactly that, and be off-tab and submit it to claude as well. Enjoy :)

Snip a piece of your screen — or paste your clipboard — **straight into the Claude desktop app** with one keypress, without stopping what you're doing.

- **Alt + 1** → drag a box on screen → the screenshot drops into Claude's message box.
- **Alt + 2** → copies the text you have **highlighted** and sends it to Claude.
- **Alt + 3** → **selects everything** on the page, copies it, and sends it to Claude.
- **Alt + 0** → post it (presses Enter in Claude).

You stay on your own screen the whole time — ClaudeSnap flicks over to Claude, drops the content, and flicks back. All three keys are yours to change (see [Customising](#customising)).

> Works with the **Claude desktop app** on Windows. It uses the app you already have — no API key, no account signup, nothing extra.

---

## Install (2 minutes)

1. **Install AutoHotkey v2** (free, tiny) → https://www.autohotkey.com/ → click *Download v2*.
2. **Download this repo**: green **Code** button → **Download ZIP** → unzip it anywhere (e.g. your Documents).
3. **Double-click `claude-snip.ahk`.**

That's it. A small green **H** icon appears in your system tray (bottom-right, near the clock) — ClaudeSnap is running. Open the Claude desktop app, highlight some text anywhere, and try **Alt + 2**.

---

## How to use it

| Do this | Press |
|---|---|
| Screenshot part of your screen into Claude | **Alt + 1**, then drag a box |
| Send the text you've highlighted | **Alt + 2** |
| Send everything on the page (select-all) | **Alt + 3** |
| Post the message | **Alt + 0** |

Typical flow: highlight some text → **Alt+2** → **Alt+0** to send. Or **Alt+1**, drag a box, **Alt+0**. Never leaving your work.

Prefer it to send the screenshot the instant you finish dragging? Set `AutoPostOnSnip = 1` in the config (below) and you can skip the Post key.

---

## Customising

Everything is in **`config.ini`** — right-click the tray icon → **Edit hotkeys (config.ini)**. Change what you like, save, then right-click the tray icon → **Reload after editing**.

Hotkey symbols: `^` = Ctrl, `!` = Alt, `+` = Shift, `#` = Windows key.
So `!1` is Alt+1, `+#a` is Shift+Win+A, and `^!s` would be Ctrl+Alt+S.
(Heads up: Ctrl+Alt combos can clash with **AltGr** on some keyboards and silently do nothing — that's why the defaults are plain Alt.)

---

## Start automatically when Windows boots (optional)

1. Press **Win + R**, type `shell:startup`, press Enter.
2. Right-click `claude-snip.ahk` → **Show more options** → **Create shortcut**, and drop the shortcut into that folder.

Now it runs every time you log in.

---

## Turn it into a single .exe (optional)

If you'd rather not install AutoHotkey on every machine, right-click `claude-snip.ahk` → **Compile Script** (installed with AutoHotkey) to produce a standalone `.exe` that runs on any Windows PC. Keep `config.ini` next to it.

---

## Troubleshooting

- **"Claude window not found"** — make sure the Claude desktop app is open. If it still can't find it, edit `config.ini` and set `WinMatch = Claude`, then Reload.
- **The screenshot doesn't paste** — some setups are slow to attach the image; open `config.ini` and it works the same, just give it a beat. If a snip fails, press the key again.
- **Quick flicker to Claude and back** — that's expected. Windows won't let one app type into another without briefly focusing it; ClaudeSnap does that in a blink and returns you. Set `RestoreFocus = 0` if you'd rather it stay on Claude.

---

## Notes

Only the **desktop app** is supported for now (browser Claude focuses differently). ClaudeSnap never sees your messages or clipboard contents leave your PC — it's just keystrokes.

MIT licensed. Do what you like with it.
