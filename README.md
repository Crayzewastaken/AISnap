# AI Snap

I basically wanted a way to have my screenshots and texts (that i copy/paste) automatically be sent to the AI chat I have open. This way, I am saving time by being able to have it do exactly that, and be off-tab and submit it as well. Enjoy :)

Talk to your AI, snip a piece of your screen, or send the text you've highlighted — **straight into your AI chat** with one keypress, without stopping what you're doing.

- **Alt + 1** → **talk to your AI** — brings the chat up so you can dictate into it (see [Voice](#voice-dictation)).
- **Alt + 2** → drag a box on screen → the screenshot goes in.
- **Alt + 3** → sends the text you have **highlighted**.
- **Alt + 4** → **selects everything** on the page and sends it.
- **Alt + 0** → send by hand (only needed if you turn auto-send off).

**Say something about it first.** When you snip or copy, a small **Send to AI** box pops up. Type whatever you want to say, grab more bits while you're at it — another screenshot, more highlighted text — and it all goes across in **one message** when you hit Enter. See [The composer box](#the-composer-box).

Want it to just fire straight through with no box? Untick *"Open the composer so I can add a note first"* in Settings — then each key drops the content in *and hits Enter* on its own.

You stay on your own screen the whole time — AI Snap flicks over to the AI app, drops the content, and flicks back. Every key is yours to change (see [Customising](#customising)).

> Works with **Claude**, **ChatGPT**, **Antigravity** — and anything else you add. It uses the desktop apps you already have: no API key, no signup, nothing extra.
>
> Not just AI, either — point it at **Word**, **Excel**, **T3** or any other program on your PC and your snips land there instead. See [Sending to any app](#sending-to-any-app).

By default it sends to **whichever supported app you used most recently**, so you can bounce between Claude and ChatGPT without changing a setting. You can also pin one.

---

## What's new

- **Send it anywhere.** Settings now opens on your list of apps. Hit **Running apps**, click the one you want, and your snips go there from now on — Word, Excel, a browser, T3, anything. Or **Click an app** and just click it on your taskbar. See [Sending to any app](#sending-to-any-app).
- **A settings card, not a dialog.** Same dark rounded look as the composer, and it follows your theme as you pick it. Your apps are a list you can add to, pick from and remove from with a ✕ — no dropdown to hunt through, and no pop-ups: the selected app's name is a box you type in, right there in the list.
- **Keys read like keys.** They show as *Alt + 2*, and clicking one asks you to press the combo you want.
- **A composer box.** Snip or copy and a little window pops up. Type a note, hit Enter, and it lands in your AI chat as one message.
- **Stack things up.** Keep snipping and copying while it's open — a screenshot, a paragraph, another screenshot. It all goes across together, in order.
- **Store button.** Not ready to send? Hit Store. It closes and keeps everything, including what you'd half-typed. Snip something two minutes later and it opens back up with your first grab still sitting there. Build a message over as long as you like, then send once.
- **Send / Store / Cancel** — send it, park it, or bin it. The tray tooltip tells you how many are waiting.
- **Drop a bad grab** with the ✕ next to it.
- **Enter** sends · **Shift+Enter** new line · **Esc** stores, so you can't lose a message by tapping it.
- **Three themes** — Claude Code (default), Codex, Gemini. Settings → *Look*.
- **Modern look.** Frameless rounded card, rounded buttons that light up under the mouse, no 90s grey dialog. Drag it by the heading.
- **New tray icon** — a little bot instead of AutoHotkey's green H.
- **Works in any program.** It's AI Snap's own window, so Word, Chrome, a PDF, a game, your email — all the same. It hides itself while you drag a snip so it never lands in your own screenshot.
- **Don't want the box?** Settings → untick it, and every key fires straight through like before.

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

Typical flow: highlight some text → **Alt+3** → type what you want to ask about it → **Enter**. Or **Alt+2**, drag a box, say your piece, Enter. Never leaving your work.

---

## The composer box

Snip or copy anything and this little box appears:

- **Type a note** — it gets sent underneath whatever you grabbed.
- **Keep grabbing** — press **Alt+2**, **Alt+3** or **Alt+4** again while it's open and the new bit joins the list. A screenshot, a paragraph you copied and your own question all arrive as **one message**.
- Grabbed the wrong thing? Click the **✕** next to it.
- Drag it around by its heading — it has no title bar, it's just a card.

Three buttons:

| Button | What it does |
|---|---|
| **Send** | The whole lot goes to your AI as one message. |
| **Store** | Puts the box away and **keeps everything** — list *and* what you'd half-typed. Nothing is sent. |
| **Cancel** | Throws it all away. |

**Store** is the one that lets you build a message over time. Snip an error → **Store**. Two minutes later, snip the log and copy a line of code → the box opens back up with the first snip still sitting there. Add your question, hit **Send**, and it all arrives together.

While something's waiting, the tray icon tooltip tells you how many.

**Enter** sends · **Shift+Enter** new line · **Esc** stores (so you never lose a thing by tapping it).

It's AI Snap's own window, so it works the same whether you grabbed from Word, a browser, a PDF, a game or your email — nothing is added to the program you're in, and the box hides itself while you're dragging a snip so it never ends up in your own screenshot.

Don't want it? Settings → untick *"Open the composer so I can add a note first"*.

### Themes

Settings → **Look**. Three to pick from, all dark:

| Theme | |
|---|---|
| **Claude Code** | Warm dark with the Claude orange. The default. |
| **Codex** | Near-black terminal look, monospaced, green. |
| **Gemini** | Cool dark grey with Google blue. |

Or set it by hand: `Theme = Codex` under `[Look]` in `config.ini`.

---

## Voice dictation

**Alt + 1** lets you just talk to your AI. It brings the chat window up, waits while you dictate, then sends what you said.

It works with whatever dictation app you already use — AI Snap doesn't do the transcribing. A good free one is **[Handy](https://handy.computer)**: open source, runs entirely offline, push-to-talk.

**Get Handy** — right-click the tray icon → **Get Handy (voice dictation)…**, or run:

```bash
winget install --id cjpais.Handy -e
```

Already have it? Nothing to do — AI Snap uses whatever is already installed.

How it goes:

1. Press **Alt + 1** — your AI chat comes to the front.
2. Hold your usual push-to-talk key (Handy's is `Ctrl+Space` out of the box) and say your piece.
3. Let go. Your words get typed into the chat and sent automatically.

Tell AI Snap which key you use in **Settings → "My dictation push-to-talk key"** — it must match Handy's **Transcribe Shortcut** (*Handy → General*). Leave Handy's **Push To Talk** switched on.

If messages get sent before you've finished, raise `Wait` under `[Dictation]` in `config.ini` — that's how long AI Snap pauses after you stop talking to let the transcription land (2500 ms by default). Lower it if you're left waiting around.

---

## Customising

**Easiest way:** double-click the tray icon (or right-click → **Settings…**). The card opens on your list of apps — click the one to send to, click a key to change it, flip the options, hit **Save and reload**. Done.

Prefer editing by hand? Everything lives in **`config.ini`** (tray → **Edit config.ini directly**, then **Reload**).
Hotkey symbols there: `^` = Ctrl, `!` = Alt, `+` = Shift, `#` = Windows key — so `!1` is Alt+1.
(Heads up: Ctrl+Alt combos can clash with **AltGr** on some keyboards and silently do nothing — that's why the defaults are plain Alt.)

### Sending to any app

It doesn't have to be an AI. Open **Settings** (double-click the tray icon) and the top of the card is your list of apps. Click one to send there from now on, or leave it on **Auto**.

Three ways to add one:

| Button | What it does |
|---|---|
| **Running apps** | Shows everything you have open. Click it, done. The quickest one. |
| **Click an app** | The card gets out of the way and you click the app on your taskbar. **Esc** to back out; it gives up after 20 seconds. |
| **Browse…** | For apps that aren't running. The normal Windows picker, opened at your Start menu. |

Nothing pops up — the app just appears in the list, selected, with its **name in a box you can type in right there**. Add one and the cursor is already in it with the name highlighted, so a page title that came out too long can be typed straight over. Click anything else and the new name is kept; press **Esc** and it isn't.

Each app in the list has two more controls:

- **Enter / no ↵** — click to flip it. **Enter** for a chat box, where Enter is what actually sends the message. **no ↵** for a document, where Enter would just leave a blank line in your work.
- **✕** — removes it from the list for good.

And on the selected app, a **where to type** button. See below.

### Where to type

Some apps come to the front with the cursor nowhere useful — browsers especially, because a web page decides for itself where its caret sits, and nothing outside the browser can move it. So you show AI Snap once.

Select the app, click **where to type**, and it brings that app up and gets out of the way. Click inside the box you type in — the chat composer, the search field, wherever — and that's it. From then on it clicks there for you before pasting. **Esc** during the pick forgets it again.

The spot is stored as a fraction of the window rather than a screen position, so it still lands after you move the window, resize it, maximise it, or drag it to another monitor. It works the same in any program; browsers are just where you'll want it most.

Apps are saved the moment you add them, so they're still there next time even if you hit Cancel.

> **Browsers** are added as the browser, not as one tab — `ahk_exe opera.exe`. Whatever tab you're on when you send is the one it lands in. Pinning to a tab's title only works until that title changes, which for a browser is about a minute.
>
> Some Microsoft Store apps don't show up in the Start menu folder. Use **Running apps** or **Click an app** instead.

### Adding one by hand

Open `config.ini` and add a line under `[Apps]`:

```ini
Name = window to look for | how to start it (optional) | press Enter? (optional)
```

For example:

```ini
Perplexity = ahk_exe Perplexity.exe | Perplexity.AI_abc123!App | 1
Excel = ahk_exe EXCEL.EXE | | 0
```

- **Window to look for** is usually `ahk_exe TheApp.exe`. To find the exe name, open the app and check Task Manager → Details. You can also match on the window title, e.g. `Gemini ahk_exe chrome.exe` for a browser tab, or just `Word` to match `Report.docx - Word`.
- **How to start it** is a full path to an `.exe` or `.lnk`, or an app id — run `Get-StartApps` in PowerShell to list them. Leave it blank and AI Snap just won't auto-launch that one.
- **Press Enter?** is `1` for chat boxes, `0` for documents. Leave it out and it's `1`.

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

- **"No app found"** — make sure one of your apps is open, or check its entry under `[Apps]` in `config.ini` matches the real exe name.
- **It sends to the wrong app** — open Settings and pin the one you want in the **Send to** dropdown instead of leaving it on Auto.
- **It adds a blank line to my document** — that app is set to press Enter. Change its last field to `0` under `[Apps]` in `config.ini`, or re-add it with **Choose an app…** and answer **No**.
- **"Nothing dictated"** — AI Snap waited 30s and never saw your push-to-talk key. Check Handy is running, and that the key in Settings matches Handy's.
- **Dictation sends half a sentence** — raise `Wait` under `[Dictation]` in `config.ini`.
- **The screenshot doesn't paste** — some apps are slow to attach the image. Raise `AttachWait` under `[Behavior]` in `config.ini` (400 ms by default), or just press the key again.
- **"Nothing to paste from the clipboard"** — that's the app you sent to, telling you Ctrl+V arrived at an empty clipboard. Update; AI Snap now waits for each grab to land before pasting it. If it happens again, `Debug = 1` writes a "clipboard never came back" line naming the grab that failed.
- **It sends to the wrong browser tab** — it doesn't pick tabs, it picks the browser, and lands in whatever tab you're on. An old entry pinned to one tab's title (`Some Page ahk_exe opera.exe`) will stop matching once that title changes — rename it in Settings and the match is rebuilt as just the browser.
- **Nothing arrives in a browser at all** — a Chromium browser can come to the front without anything inside it holding the keyboard, so the paste had nowhere to go. AI Snap now hands the keyboard to the page itself. If text still doesn't appear, set **where to type** for that app (see [above](#where-to-type)) — the page decides where a paste lands, and pointing at the box once is the only thing that can settle it from outside.
- **Quick flicker to the AI app and back** — that's expected. Windows won't let one app type into another without briefly focusing it; AI Snap does that in a blink and returns you. Untick *"Return to my window"* if you'd rather it stay.
- **Still nothing?** Set `Debug = 1` in `config.ini` and Reload. An `ai-snap.log` appears next to the script showing what fired.

---

## Notes

Desktop apps work best (a browser tab can be matched by title, but only when it's the active tab). AI Snap never sends your messages or clipboard anywhere — it's just keystrokes on your own PC.

MIT licensed. Do what you like with it.
