# AI Snap

I basically wanted a way to have my screenshots and texts (that i copy/paste) automatically be sent to the AI chat I have open. This way, I am saving time by being able to have it do exactly that, and be off-tab and submit it as well. Enjoy :)

Snip a piece of your screen — or send the text you've highlighted — **straight into your AI chat** with one keypress, without stopping what you're doing.

- **Alt + 1** → drag a box on screen → the screenshot drops into the message box.
- **Alt + 2** → copies the text you have **highlighted** and sends it.
- **Alt + 3** → **selects everything** on the page, copies it, and sends it.
- **Alt + 0** → post it (presses Enter).

You stay on your own screen the whole time — AI Snap flicks over to the AI app, drops the content, and flicks back. Every key is yours to change (see [Customising](#customising)).

> Works with **Claude**, **ChatGPT**, **Antigravity** — and anything else you add. It uses the desktop apps you already have: no API key, no signup, nothing extra.

By default it sends to **whichever supported app you used most recently**, so you can bounce between Claude and ChatGPT without changing a setting. You can also pin one.

---

## Install (2 minutes)

1. **Install AutoHotkey v2** (free, tiny) → https://www.autohotkey.com/ → click *Download v2*.
2. **Download this repo**: green **Code** button → **Download ZIP** → unzip it anywhere (e.g. your Documents).
3. **Double-click `ai-snap.ahk`.**

That's it. A small green **H** icon appears in your system tray (bottom-right, near the clock) — AI Snap is running. Open your AI app, highlight some text anywhere, and try **Alt + 2**.

---

## How to use it

| Do this | Press |
|---|---|
| Screenshot part of your screen into the chat | **Alt + 1**, then drag a box |
| Send the text you've highlighted | **Alt + 2** |
| Send everything on the page (select-all) | **Alt + 3** |
| Post the message | **Alt + 0** |

Typical flow: highlight some text → **Alt+2** → **Alt+0** to send. Or **Alt+1**, drag a box, **Alt+0**. Never leaving your work.

Prefer it to send the screenshot the instant you finish dragging? Tick *"Send screenshot the moment I finish snipping"* in Settings.

---

## Customising

**Easiest way:** double-click the tray icon (or right-click → **Settings…**). A little window opens — pick which AI app to send to, click any box and press the keys you want, tick your options, hit **Save & Reload**. Done.

Prefer editing by hand? Everything lives in **`config.ini`** (tray → **Edit config.ini directly**, then **Reload**).
Hotkey symbols there: `^` = Ctrl, `!` = Alt, `+` = Shift, `#` = Windows key — so `!1` is Alt+1.
(Heads up: Ctrl+Alt combos can clash with **AltGr** on some keyboards and silently do nothing — that's why the defaults are plain Alt.)

### Adding another AI app

Open `config.ini` and add a line under `[Apps]`:

```ini
Name = window to look for | how to start it (optional)
```

For example:

```ini
Perplexity = ahk_exe Perplexity.exe | Perplexity.AI_abc123!App
```

- **Window to look for** is usually `ahk_exe TheApp.exe`. To find the exe name, open the app and check Task Manager → Details. You can also match on the window title, e.g. `Gemini ahk_exe chrome.exe` for a browser tab.
- **How to start it** is either a full path to an `.exe`, or an app id — run `Get-StartApps` in PowerShell to list them. Leave it blank and AI Snap just won't auto-launch that one.

Apps included out of the box: Claude, ChatGPT, ChatGPT Classic, Antigravity. Delete any you don't use.

---

## Start automatically when Windows boots (optional)

1. Press **Win + R**, type `shell:startup`, press Enter.
2. Right-click `ai-snap.ahk` → **Show more options** → **Create shortcut**, and drop the shortcut into that folder.

Now it runs every time you log in.

---

## Turn it into a single .exe (optional)

If you'd rather not install AutoHotkey on every machine, right-click `ai-snap.ahk` → **Compile Script** (installed with AutoHotkey) to produce a standalone `.exe` that runs on any Windows PC. Keep `config.ini` next to it.

---

## Troubleshooting

- **"No AI app found"** — make sure one of your AI apps is open, or check its entry under `[Apps]` in `config.ini` matches the real exe name.
- **It sends to the wrong app** — open Settings and pin the one you want in the **Send to** dropdown instead of leaving it on Auto.
- **The screenshot doesn't paste** — some apps are slow to attach the image. If a snip fails, just press the key again.
- **Quick flicker to the AI app and back** — that's expected. Windows won't let one app type into another without briefly focusing it; AI Snap does that in a blink and returns you. Untick *"Return to my window"* if you'd rather it stay.
- **Still nothing?** Set `Debug = 1` in `config.ini` and Reload. An `ai-snap.log` appears next to the script showing what fired.

---

## Notes

Desktop apps work best (a browser tab can be matched by title, but only when it's the active tab). AI Snap never sends your messages or clipboard anywhere — it's just keystrokes on your own PC.

MIT licensed. Do what you like with it.
