# AI Snap

I basically wanted a way to have my screenshots and texts (that i copy/paste) automatically be sent to the AI chat I have open. This way, I am saving time by being able to have it do exactly that, and be off-tab and submit it as well. Enjoy :)

Talk to your AI, snip a piece of your screen, or send the text you've highlighted — **straight into your AI chat** with one keypress, without stopping what you're doing.

- **Alt + 1** → **talk to your AI** — brings the chat up so you can dictate into it (see [Voice](#voice-dictation)).
- **Alt + 2** → drag a box on screen → the screenshot goes in.
- **Alt + 3** → sends the text you have **highlighted**.
- **Alt + 4** → **selects everything** on the page and sends it.
- **Alt + 0** → send by hand (only needed if you turn auto-send off).

**Everything sends itself.** By default each of these drops the content in *and hits Enter*, so you're done in one keypress. Prefer to add a note before it goes? Untick *"Send to the AI automatically every time"* in Settings and use **Alt + 0** when you're ready.

You stay on your own screen the whole time — AI Snap flicks over to the AI app, drops the content, and flicks back. Every key is yours to change (see [Customising](#customising)).

> Works with **Claude**, **ChatGPT**, **Antigravity** — and anything else you add. It uses the desktop apps you already have: no API key, no signup, nothing extra.

By default it sends to **whichever supported app you used most recently**, so you can bounce between Claude and ChatGPT without changing a setting. You can also pin one.

---

## Install (2 minutes)

1. **Install AutoHotkey v2** (free, tiny) → https://www.autohotkey.com/ → click *Download v2*.
2. **Download this repo**: green **Code** button → **Download ZIP** → unzip it anywhere (e.g. your Documents).
3. **Double-click `ai-snap.ahk`.**
4. *Optional, for voice:* install **[Handy](https://handy.computer)** — free, open source, offline dictation.

That's it. A small green **H** icon appears in your system tray (bottom-right, near the clock) — AI Snap is running. Open your AI app, highlight some text anywhere, and try **Alt + 3**.

---

## How to use it

| Do this | Press |
|---|---|
| Say something to your AI | **Alt + 1**, then dictate |
| Screenshot part of your screen into the chat | **Alt + 2**, then drag a box |
| Send the text you've highlighted | **Alt + 3** |
| Send everything on the page (select-all) | **Alt + 4** |
| Send by hand (if auto-send is off) | **Alt + 0** |

Typical flow: highlight some text → **Alt+3**. That's it — it's already sent. Or **Alt+2**, drag a box, done. Never leaving your work.

---

## Voice dictation

**Alt + 1** lets you just talk to your AI. It brings the chat window up, waits while you dictate, then sends what you said.

It works with whatever dictation app you already use — AI Snap doesn't do the transcribing. A good free one is **[Handy](https://handy.computer)**: open source, runs entirely offline, push-to-talk.

How it goes:

1. Press **Alt + 1** — your AI chat comes to the front.
2. Hold your usual push-to-talk key (Handy's is `Ctrl+Space` out of the box) and say your piece.
3. Let go. Your words get typed into the chat and sent automatically.

Tell AI Snap which key you use in **Settings → "My dictation push-to-talk key"** — it must match the one set in Handy (*Handy → Settings → Shortcuts → transcribe*).

If messages get sent before you've finished, raise `Wait` under `[Dictation]` in `config.ini` — that's how long AI Snap pauses after you stop talking to let the transcription land (2500 ms by default). Lower it if you're left waiting around.

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
- **"Nothing dictated"** — AI Snap waited 30s and never saw your push-to-talk key. Check Handy is running, and that the key in Settings matches Handy's.
- **Dictation sends half a sentence** — raise `Wait` under `[Dictation]` in `config.ini`.
- **The screenshot doesn't paste** — some apps are slow to attach the image. If a snip fails, just press the key again.
- **Quick flicker to the AI app and back** — that's expected. Windows won't let one app type into another without briefly focusing it; AI Snap does that in a blink and returns you. Untick *"Return to my window"* if you'd rather it stay.
- **Still nothing?** Set `Debug = 1` in `config.ini` and Reload. An `ai-snap.log` appears next to the script showing what fired.

---

## Notes

Desktop apps work best (a browser tab can be matched by title, but only when it's the active tab). AI Snap never sends your messages or clipboard anywhere — it's just keystrokes on your own PC.

MIT licensed. Do what you like with it.
