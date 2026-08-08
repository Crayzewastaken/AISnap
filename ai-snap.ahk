#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================================
;  AI Snap  —  send screenshots and text straight into your AI chat app.
;
;  Works with Claude, ChatGPT, Antigravity, or anything else you add.
;  By default it sends to whichever supported app you used most recently.
;
;  You don't need to edit this file — double-click the tray icon for settings.
; ============================================================================

cfg := A_ScriptDir "\config.ini"
; config.ini is yours — it isn't in the repo, so updating never overwrites
; your apps and keys. First run copies the shipped defaults into place.
if (!FileExist(cfg) && FileExist(A_ScriptDir "\config.example.ini"))
    try FileCopy(A_ScriptDir "\config.example.ini", cfg)
SetTitleMatchMode(2)              ; allow partial window-title matches
InstallKeybdHook()                ; see keys even when another app swallows them

; --- settings (read from config.ini, with safe fallbacks) -------------------
global Apps         := LoadApps()
global LastApp      := 0          ; the app we last sent to — see EnterOK()
global LastTarget   := 0          ; and its window, so we paste into that one
global Active       := IniRead(cfg, "Target",   "Active",         "Auto")
global RestoreFocus := IniRead(cfg, "Behavior", "RestoreFocus",   "1")
global AutoSend     := IniRead(cfg, "Behavior", "AutoSend",       "1")
global Composer     := IniRead(cfg, "Behavior", "Composer",       "1")
global Theme        := IniRead(cfg, "Look",     "Theme",          "Claude Code")
global AttachWait   := IniRead(cfg, "Behavior", "AttachWait",     "400")
global Debug        := IniRead(cfg, "Behavior", "Debug",          "0")

; --- the composer's state (see the composer section further down) -----------
global Comp      := 0     ; the composer window while it's open, 0 when it isn't
global CompItems := []    ; what's attached so far: [{label, data, wait}]
global CompPrev  := 0     ; the window to hand focus back to when we're done
global CompNote  := ""    ; your typed note, kept while the box is put away
global CompEdit  := 0, CompHead := 0

global DictationKey  := IniRead(cfg, "Dictation", "Key",  "F4")
global DictationWait := IniRead(cfg, "Dictation", "Wait", "2500")

; --- the floating button (see the badge section further down) ---------------
; Declared up here, not next to its own code: the auto-execute section calls
; ShowBadge() before it ever reaches that part of the file, and reading a
; global that hasn't been assigned yet stops the whole script dead on an
; error box you can't see behind everything else.
global Badge      := 0        ; the window, 0 when it isn't up
global BadgeWait  := false    ; a click has landed, waiting to see if a second one does
global BadgeLast  := 0        ; when that click was
global BadgeAt    := [0, 0]   ; and where, so a second one has to be near it
global BadgeFrom  := [0, 0, 0, 0]   ; mouse x,y and window x,y when you pressed
global BadgeMoved := false

; --- fill mode (see the fill section further down) --------------------------
global Filling     := false   ; armed: every copy lands and moves on
global FillLast    := 0       ; when the last one landed, for the idle timeout
global FillBadge   := 0       ; the little "filling" tag on screen
global FillAdvance := IniRead(cfg, "Fill", "Advance", "Tab")
global FillTimeout := SafeInt(IniRead(cfg, "Fill", "Timeout", "120"), 120)
global ClipMine    := 0       ; >0 while WE are the ones using the clipboard

; config.ini is a text file anyone can edit by hand, and a number that isn't
; one blows up inside a timer where nobody sees the error.
SafeInt(v, dflt) => IsInteger(v) ? Integer(v) : dflt

; Fill mode reacts to every clipboard change. Our own snips, copies and
; composer sends are clipboard changes too — hold it off while we work, or
; an Alt+2 snip meant for your AI gets pasted into the spreadsheet as well.
ClipHold() {
    global ClipMine
    ClipMine++
}
ClipRelease() {
    global ClipMine
    if (ClipMine > 0)
        ClipMine--
}

keyDict := IniRead(cfg, "Hotkeys", "Dictate",        "!1")
keySnip := IniRead(cfg, "Hotkeys", "SnipAndSend",    "!2")
keySel  := IniRead(cfg, "Hotkeys", "CopySelection",  "!3")
keyAll  := IniRead(cfg, "Hotkeys", "CopyAllOnPage",  "!4")
keyPost := IniRead(cfg, "Hotkeys", "Post",           "!0")
keyFill := IniRead(cfg, "Hotkeys", "Fill",           "!9")

; --- bind the hotkeys -------------------------------------------------------
Hotkey(keyDict, DictateToAI)
Hotkey(keySnip, SnipAndSend)
Hotkey(keySel,  CopySelectionToAI)
Hotkey(keyAll,  CopyAllToAI)
Hotkey(keyPost, PostToAI)
Hotkey(keyFill, ToggleFill)

; The little bot, instead of AutoHotkey's H. Missing icon isn't worth dying over.
try TraySetIcon(A_ScriptDir "\ai-snap.ico")
OnMessage(0x201, DragCard)                  ; 0x201 = left mouse button down
OnMessage(0x203, DragCard)                  ; 0x203 = ...and that was a double

; Enter sends from the composer box (Shift+Enter still makes a new line).
; Registered once, and only ever live while that window is the active one.
HotIfWinActive("Send to AI ahk_class AutoHotkeyGUI")
Hotkey("Enter", ComposerSend)
HotIf()

; Watch for your dictation key being released. The "~" means we only listen —
; the keystroke still reaches Handy exactly as normal.
global Armed := false, ArmedPrev := 0
try Hotkey("~" DictationKey " up", DictationFinished)
catch
    TrayTip("Check your dictation key", "'" DictationKey "' isn't a key name.", 3)

; --- tray menu --------------------------------------------------------------
A_TrayMenu.Delete()
A_TrayMenu.Add("Settings…", (*) => ShowSettings())
A_TrayMenu.Default := "Settings…"          ; double-click the tray icon opens it

; Left-click the tray icon and you get the same menu as right-click. One icon
; with two different behaviours is just one more thing to have to remember.
; 0x404 = AHK_NOTIFYICON, and lParam is the mouse message that caused it.
OnMessage(0x404, TrayClick)
TrayClick(wParam, lParam, *) {
    if (lParam = 0x202) {                  ; WM_LBUTTONUP
        A_TrayMenu.Show()
        return 0                           ; ...instead of the usual handling
    }
}
A_TrayMenu.Add()
A_TrayMenu.Add("Show the floating button", (*) => ToggleBadge())
A_TrayMenu.Add("Get Handy (voice dictation)…", (*) => InstallHandy())
A_TrayMenu.Add("Edit config.ini directly", (*) => Run(cfg))
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
UpdateTrayTip()

; Run as a normal user, always. Elevated, the keyboard hook and the keystrokes
; it sends reach admin windows too, which turns a small tool into a large one.
if A_IsAdmin
    TrayTip("Running as administrator",
            "AI Snap doesn't need it, and it can reach admin windows this way."
          . " Start it normally instead.", 2)

; The little round button on screen, unless you've put it away.
if (IniRead(cfg, "Look", "Button", "1") = "1")
    ShowBadge()

; Were we filling when the settings window saved and restarted us? Pick it
; back up. The flag is consumed on the way in, so starting AI Snap fresh
; tomorrow never comes up already armed.
if (IniRead(cfg, "Fill", "Resume", "0") = "1") {
    try IniWrite("0", cfg, "Fill", "Resume")
    SetTimer(StartFill, -900)
}

; First time here? Say hello. On a timer so the auto-execute section finishes
; and the tray icon is up before the card appears on top of it.
if (IniRead(cfg, "Behavior", "Welcomed", "0") != "1")
    SetTimer(ShowWelcome, -700)
else
    TrayTip("AI Snap is running",
            "Talk: " keyDict "   Snip: " keySnip "   Copy: " keySel "   All: " keyAll, 1)

; ============================================================================
;  actions
; ============================================================================

; Talk to your AI: focus the chat, wait while you dictate, then send.
; Handy (or any dictation tool) types into whatever window has focus — so we
; put the AI chat in front first, then let YOUR push-to-talk key do the talking.
DictateToAI(*) {
    global RestoreFocus, AutoSend, DictationKey, DictationWait
    Log("Dictate fired")
    global Armed, ArmedPrev, DictationKey
    prev := WinActive("A")
    KeyWait("Alt", "T1")              ; never hold Alt near F4 — that's Alt+F4
    if !FocusTarget()
        return
    ArmedPrev := prev
    Armed := true                     ; the next dictation gets sent for us
    SetTimer(Disarm, -30000)          ; ...unless you never get around to it
    TrayTip("Listening…", "Hold " DictationKey " and talk.", 1)
}

; Fires when you let go of the dictation key, but only if Alt+1 armed us.
DictationFinished(*) {
    global Armed, ArmedPrev, DictationWait
    if !Armed
        return                        ; ordinary dictation — none of our business
    Armed := false
    Log("dictation finished — waiting " DictationWait "ms")
    Sleep(DictationWait)              ; let it transcribe and type
    Submit()
    GoBack(ArmedPrev)
}

; Stop waiting if you pressed Alt+1 and then wandered off.
Disarm() {
    global Armed
    if Armed {
        Armed := false
        Log("disarmed — no dictation within 30s")
        TrayTip("Nothing dictated", "Is Handy running, and is its key right?", 2)
    }
}

; Snip a region of the screen and drop it into your AI chat.
SnipAndSend(*) {
    global Comp, CompPrev, Composer, AttachWait
    Log("Snip fired")
    prev := Comp ? CompPrev : WinActive("A")
    if Comp
        Comp.Hide()                   ; keep the composer out of your own screenshot
    KeyWait("Alt", "T1")              ; let go of Alt so the snip key isn't mangled
    ClipHold()                        ; this snip is ours, not fill mode's
    try {
        A_Clipboard := ""             ; clear so we can detect the new snip
        Send("#+s")                   ; Windows built-in "snip region to clipboard"
        if !ClipWait(60, 1) {         ; wait up to 60s for the snip (1 = images too)
            if Comp
                ShowComposer(prev)    ; snip cancelled — put the box back
            return
        }
        if (Composer = "1") {
            Attach("Screenshot", prev, AttachWait)
            return
        }
        PasteIntoAI(prev, AttachWait)
    }
    finally
        ClipRelease()
}

; Copy whatever text is highlighted right now, then send it.
CopySelectionToAI(*) {
    Log("CopySelection fired")
    GrabTextToAI("^c", "Text")
}

; Select everything on the page, copy it, then send it.
CopyAllToAI(*) {
    Log("CopyAll fired")
    GrabTextToAI("^a^c", "Whole page")
}

; Send / post the current message.
PostToAI(*) {
    Log("Post fired")
    Post(WinActive("A"))
}

; ============================================================================
;  fill mode — copy, copy, copy, and it lands in the next cell each time
;
;  Press the fill key once and AI Snap starts watching your clipboard. Every
;  time you copy anything, it goes into your chosen app and then presses Tab
;  (or Enter, or whatever you set) to move on. Copy the next thing and it
;  lands in the next cell. Transcribing an invoice into a spreadsheet stops
;  being alt-tab, click, paste, alt-tab, click, paste.
;
;  It is armed until you say otherwise, so it says so on screen the whole
;  time and stops on its own if you wander off.
; ============================================================================
ToggleFill(*) {
    global Filling, SetGui
    Filling ? StopFill("you turned it off") : StartFill()
    if SetGui
        RefreshSettings()             ; so the switch shows what's actually true
}

StartFill() {
    global Filling, FillLast, FillAdvance
    KeyWait("Alt", "T1")
    ; Check there's somewhere to put things, but don't go there — arming
    ; shouldn't drag you off whatever you're about to copy from.
    if !FindTarget() {
        TrayTip("Nothing to fill", "Open the app you want to fill first.", 2)
        return
    }
    Filling := true, FillLast := A_TickCount
    OnClipboardChange(FillPaste, 1)
    Hotkey("~Escape", StopFillKey, "On")
    SetTimer(FillWatch, 1000)
    ShowFillBadge()
    Log("fill armed, advance=" FillAdvance)
}

; Esc pressed inside one of OUR windows is closing that window — the settings
; card, the composer, the hello. It isn't a request to stop filling, and
; treating it as one meant closing settings quietly switched filling off.
StopFillKey(*) {
    try {
        if (a := WinActive("A"))
            if (WinGetPID("ahk_id " a) = DllCall("GetCurrentProcessId"))
                return
    }
    StopFill("you pressed Esc")
}

StopFill(why) {
    global Filling, FillBadge
    if !Filling
        return
    Filling := false
    OnClipboardChange(FillPaste, 0)
    try Hotkey("~Escape", StopFillKey, "Off")
    SetTimer(FillWatch, 0)
    if FillBadge {
        try FillBadge.Destroy()
        FillBadge := 0
    }
    Log("fill stopped — " why)
    TrayTip("Filling stopped", why, 1)
}

; Fires on every clipboard change while armed. Type is 0 when the clipboard
; was emptied, which is what our own snip does before it grabs — ignore those.
FillPaste(type) {
    global Filling, FillLast, FillAdvance, ClipMine
    if (!Filling || !type || ClipMine)
        return
    prev := WinActive("A")
    if !FocusTarget() {
        StopFill("couldn't reach the app")
        return
    }
    FillLast := A_TickCount
    if !Paste() {                     ; don't advance a cell we never filled
        GoBack(prev)
        return
    }
    Sleep(90)
    if (FillAdvance != "" && FillAdvance != "None")
        Send("{" FillAdvance "}")
    Sleep(40)
    GoBack(prev)
    Log("filled one, advanced with " FillAdvance)
}

; Armed and forgotten is how you paste into something you didn't mean to.
FillWatch() {
    global Filling, FillLast, FillTimeout
    if (Filling && FillTimeout > 0
        && (A_TickCount - FillLast) > FillTimeout * 1000)
        StopFill("nothing copied for " FillTimeout "s")
}

; A small tag in the bottom corner. Being armed changes what every copy does,
; so it should never be something you have to remember you switched on.
ShowFillBadge() {
    global FillBadge, FillAdvance, Active
    t := ThemeNow()
    FillBadge := g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20", "AI Snap filling")
    g.MarginX := 14, g.MarginY := 10          ; +E0x20 = clicks pass through it
    ApplyTheme(g, t)
    g.BackColor := t.accent
    g.SetFont("s10 w600 c" t.accentText, t.font)
    g.Add("Text", "xm ym", "● Filling " (Active = "Auto" ? "" : Active))
    g.SetFont("s8 w400 c" t.accentText)
    g.Add("Text", "xm y+2", "every copy lands, then " FillAdvance "  ·  Esc to stop")
    g.Show("NoActivate AutoSize")
    WinGetPos(, , &bw, &bh, "ahk_id " g.Hwnd)
    g.Move(A_ScreenWidth - bw - 24, A_ScreenHeight - bh - 64)
}

; ============================================================================
;  shared helpers
; ============================================================================

; Copy from the window you're in (using copyKeys), then paste into the AI app.
GrabTextToAI(copyKeys, label) {
    global Comp, CompPrev, Composer
    prev := Comp ? CompPrev : WinActive("A")
    KeyWait("Alt", "T1")              ; release Alt or ^c becomes ^!c and fails
    ClipHold()                        ; this copy is ours, not fill mode's
    try {
        A_Clipboard := ""             ; clear so we know when the copy lands
        Send(copyKeys)                ; the copy happens in YOUR window
        if !ClipWait(2) {             ; wait up to 2s for text
            TrayTip("Nothing copied", "No text was selected to send.", 2)
            return
        }
        if (Composer = "1") {
            Attach(label ": " Preview(A_Clipboard), prev, 120)
            return
        }
        PasteIntoAI(prev, 120)
    }
    finally
        ClipRelease()
}

; Focus the AI app, paste the clipboard, send it, then hand focus back.
PasteIntoAI(prev, settle) {
    if !FocusTarget()
        return
    if Paste() {
        Sleep(settle)                 ; let it attach before we send
        Submit()
    }
    GoBack(prev)
}

; Focus the app, press Enter, then hand focus back. (The manual send key.)
Post(prev) {
    KeyWait("Alt", "T1")
    if !FocusTarget()
        return
    if EnterOK() {                    ; nothing to "send" in a document
        Send("{Enter}")
        Sleep(80)
    }
    GoBack(prev)
}

; Chat apps need Enter to fire the message off. Word or Excel would just get a
; stray blank line, so anything added with "press Enter = no" skips it.
EnterOK() {
    global LastApp
    return !LastApp || LastApp.enter != "0"
}

; Press Enter — but only when auto-send is on and the target actually wants it.
Submit() {
    global AutoSend
    if (AutoSend = "1" && EnterOK()) {
        Log("submitting")
        Send("{Enter}")
        Sleep(80)
    }
}

; Install Handy, the free offline dictation app, via the Windows package
; manager. Already installed? winget just tells you so and changes nothing.
InstallHandy() {
    if (MsgBox("Install Handy, the free offline dictation app?`n`n"
             . "It's what powers the 'talk to my AI' key.",
               "AI Snap", "OKCancel Iconi") != "OK")
        return
    Run('powershell.exe -NoProfile -NoExit -Command '
      . '"winget install --id cjpais.Handy -e --accept-package-agreements '
      . '--accept-source-agreements"')
}

; Return to whatever the user was doing, if they asked us to.
GoBack(prev) {
    global RestoreFocus
    if (RestoreFocus = "1" && prev)
        WinActivate("ahk_id " prev)
}

; Bring the target AI window to the front — whatever state it's in.
; Handles: focused, minimised, hidden to the tray, or not running at all.
FocusTarget() {
    global LastApp, LastTarget
    LastTarget := 0
    id := FindTarget()
    if !id {                                   ; nothing open — try launching one
        if !(app := AppToLaunch()) {
            TrayTip("No app found",
                    "Open one, or pick it in Settings → Send to.", 3)
            return 0
        }
        LastApp := app
        Launch(app)
        if !WinWait(app.match, , 15) {
            TrayTip("Couldn't open " app.name, "Check its entry in config.ini.", 3)
            return 0
        }
        id := WinExist(app.match)
    }
    if (WinGetMinMax("ahk_id " id) = -1)       ; -1 = minimised
        WinRestore("ahk_id " id)
    WinShow("ahk_id " id)                       ; un-hide if it was in the tray
    WinActivate("ahk_id " id)
    ok := WinWaitActive("ahk_id " id, , 3)
    if ok {
        LastTarget := id
        GiveFocus(id)
        ClickSpot(id)
    }
    Log("FocusTarget id=" id " activated=" (ok ? "yes" : "no"))
    return ok
}

; Ctrl+V, but only into the window we actually lined up.
;
; Bringing a window to the front and typing into it are two separate moments,
; and things happen in between: a toast appears, a slow app finishes starting,
; a dialog opens. The paste would go wherever focus went — and what's on the
; clipboard might be a screenshot of your screen or a page of copied text.
; Sending a message one attachment at a time makes that gap seconds long.
Paste() {
    global LastTarget
    if (LastTarget && WinActive("A") != LastTarget) {
        Log("something else took focus — not pasting")
        return false
    }
    Send("^v")
    return true
}

; Put the caret in the box you actually type in.
;
; Inside a browser there is nothing to aim at from out here — the whole page
; is one window, and its text fields are painted pixels, so no amount of
; Win32 poking can find them. A click can though, and a click works the same
; in every program. You point at the box once and we remember the spot as a
; fraction of the window, so it still lands after you move or resize it, or
; move it to a different monitor.
; A spot is a fraction of the window, so anything outside 0 to 1 would click
; outside the window — the taskbar, the desktop, whatever app is next to it.
; The picker can only ever write a value inside the window, but config.ini is
; hand-editable and the tray menu invites you to edit it.
InWindow(v) => !IsNumber(v) ? 0.5 : Min(1, Max(0, v + 0))

ClickSpot(id) {
    global LastApp
    if (!LastApp || LastApp.spot = "")
        return
    at := StrSplit(LastApp.spot, ",")
    if (at.Length != 2)
        return
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " id)
        ; Integer(), not Round() — this script has its own Round() for corners
        ; and AHK names are case-insensitive, so the built-in is unreachable.
        x := wx + Integer(InWindow(at[1]) * ww)
        y := wy + Integer(InWindow(at[2]) * wh)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)             ; put the pointer back afterwards —
        Click(x, y)                       ; nobody asked us to move their mouse
        Sleep(120)
        MouseMove(mx, my, 0)
        Log("clicked typing spot " x "," y " in " ww "x" wh)
    }
}

; Being the front window isn't the same as being able to receive a keystroke.
; A Chromium browser comes to the front with NO child holding the keyboard
; focus, so Ctrl+V goes precisely nowhere — which is what "it doesn't work in
; the browser" turned out to be. Hand focus to the biggest visible child,
; which is the page itself rather than a background tab or a scrollbar.
GiveFocus(id) {
    try {
        if ControlGetFocus("ahk_id " id)
            return                              ; something already has it
    }
    ; Biggest wins, so we land on the page rather than a scrollbar — but only
    ; if it actually takes the focus. Chromium's "Intermediate D3D Window" is
    ; the largest child by far and is a drawing surface that silently refuses,
    ; so asking isn't enough: check afterwards and move on if it didn't stick.
    best := 0, bestArea := 0
    for hwnd in WinGetControlsHwnd("ahk_id " id) {
        try {
            if !DllCall("IsWindowVisible", "ptr", hwnd)
                continue
            ControlGetPos(, , &w, &h, hwnd)
            if (w * h <= bestArea)
                continue
            ControlFocus(hwnd)
            if ControlGetFocus("ahk_id " id)
                best := hwnd, bestArea := w * h
        }
    }
    if best {
        try ControlFocus(best)
        Log("keyboard focus → " best " (" bestArea " px)")
    } else
        Log("nothing in " id " would take the keyboard focus")
}

; WinExist hands back whatever is topmost, and for a browser that can be a
; tooltip or a half-built popup that lives for a few hundred milliseconds.
; Take the first one you could actually type into instead.
FindWindow(match) {
    for hwnd in WinGetList(match) {
        try {
            if (WinGetTitle("ahk_id " hwnd) = "")
                continue
            ; Only judge size on a window that's actually up — minimised and
            ; tray-hidden windows report nonsense, and those are the ones we
            ; most want to find.
            if (WinGetMinMax("ahk_id " hwnd) = 0
                && DllCall("IsWindowVisible", "ptr", hwnd)) {
                WinGetPos(, , &w, &h, "ahk_id " hwnd)
                if (w < 200 || h < 200)
                    continue
            }
            return hwnd
        }
    }
    return 0
}

; Which window should we send to? Honours the pinned app, else picks the
; app you used most recently (window Z-order = most recent first).
; Also remembers WHICH app we landed on, so we know whether to press Enter.
FindTarget() {
    global Apps, Active, LastApp
    LastApp := 0
    if (Active != "Auto") {
        for a in Apps {
            if (a.name = Active) {
                LastApp := a
                DetectHiddenWindows(false)
                if (id := FindWindow(a.match))
                    return id
                DetectHiddenWindows(true)       ; also catch tray-hidden windows
                return FindWindow(a.match)
            }
        }
    }
    ; Auto — visible windows first (real Z-order), then hidden ones.
    for hidden in [false, true] {
        DetectHiddenWindows(hidden)
        owned := Map()
        for a in Apps
            if (hwnd := FindWindow(a.match))    ; a real window, not a tooltip
                owned[hwnd] := a
        for hwnd in WinGetList() {              ; every window, most recent first
            if owned.Has(hwnd) {
                LastApp := owned[hwnd]
                return hwnd
            }
        }
    }
    return 0
}

; Nothing open? Work out what to start. Pinned to one app means that app or
; nothing — starting a different one behind your back would be a nasty surprise.
AppToLaunch() {
    global Apps, Active
    if (Active != "Auto") {
        for a in Apps
            if (a.name = Active)
                return a.launch != "" ? a : 0
        return 0
    }
    for a in Apps                       ; Auto — the first one that knows how
        if (a.launch != "")
            return a
    return 0
}

; Start an app: a full path to an .exe, or an app id from the Start menu.
; This is the only field in config.ini that starts a process, and config.ini
; lives in a folder you can write to — so it runs a file that actually exists
; or a plain Start-menu app id, and nothing else. Anything carrying spaces,
; quotes, & or | isn't an app id and doesn't get handed to the shell.
Launch(app) {
    if (InStr(app.launch, "\") || InStr(app.launch, ".exe")) {
        if !FileExist(app.launch) {
            Log("won't launch, no such file: " app.launch)
            return
        }
        try Run(app.launch)
        return
    }
    if RegExMatch(app.launch, "^[\w.\-]+(_[\w]+)?(![\w.\-]+)?$") {
        try Run("explorer.exe shell:AppsFolder\" app.launch)
    } else
        Log("won't launch, not an app id: " app.launch)
}

; Read the [Apps] section into a list of {name, match, launch, enter, spot}.
;   enter  optional, 0 = don't press Enter after pasting (documents)
;   spot   optional, "0.5,0.92" = where to click before typing, as a fraction
;          of the window so it survives moving, resizing and other monitors
LoadApps() {
    global cfg
    apps := []
    try section := IniRead(cfg, "Apps")
    catch
        return apps
    for line in StrSplit(section, "`n", "`r") {
        if !(eq := InStr(line, "="))
            continue
        name := Trim(SubStr(line, 1, eq - 1))
        bits := StrSplit(SubStr(line, eq + 1), "|")
        match := Trim(bits.Has(1) ? bits[1] : "")
        ent   := Trim(bits.Has(3) ? bits[3] : "")
        if (match != "")
            apps.Push({ name:   name,
                        match:  match,
                        launch: Trim(bits.Has(2) ? bits[2] : ""),
                        enter:  (ent = "" ? "1" : ent),
                        spot:   Trim(bits.Has(4) ? bits[4] : "") })
    }
    return apps
}

; One place that knows what an [Apps] line looks like, so adding a field
; doesn't mean hunting down four places that write one.
AppLine(a) => a.match " | " a.launch " | " a.enter
            . (a.spot != "" ? " | " a.spot : "")

; Pick any program on this PC to send to — Word, Excel, a browser, anything.
; Opens at the Start menu so you see the names you know, not a pile of .exe
; files. Returns an app the same shape as an [Apps] line, or 0 if cancelled.
ChooseApp() {
    ; 3 = it has to be a real file. 32 = hand us the shortcut itself, not the
    ; exe behind it — otherwise "Word" comes back as "WINWORD" and reads awful.
    path := FileSelect(35, A_StartMenuCommon "\Programs\",
                       "Choose an app to send to", "Programs (*.lnk; *.exe)")
    if !path
        return 0
    name := CleanName(RegExReplace(SubStr(path, InStr(path, "\", , -1) + 1),
                                   "\.(lnk|exe)$", ""))
    target := path
    if (SubStr(path, -4) = ".lnk")
        try FileGetShortcut(path, &target)      ; shortcuts point at the real exe
    ; Match on the exe where we can. Store apps have no exe behind the shortcut,
    ; so fall back to matching the app's name inside the window title —
    ; "Word" finds "Report.docx - Word" because partial titles already match.
    match := (target != "" && SubStr(target, -4) = ".exe")
        ? "ahk_exe " SubStr(target, InStr(target, "\", , -1) + 1)
        : name
    return { name: name, match: match, launch: path, enter: "1", spot: "" }
}

; ---- picking an app by clicking it ------------------------------------------
; Easier than hunting through the Start menu: get our window out of the way,
; you click the app on your taskbar, and whatever you land on becomes the
; target. Only works for apps that are already open, which is the usual case.
ClickApp(g) {
    g.Hide()
    Sleep(250)                          ; let focus settle on whatever was behind
    start := WinActive("A")
    Log("click-pick: waiting, focus is on " start)
    TrayTip("Click the app you want",
            "Click it on your taskbar. Esc to give up.", 1)
    id := GrabNextWindow(start)
    g.Show()
    if !id {
        Log("click-pick: nothing picked")
        TrayTip("Nothing picked", "Nothing was clicked, so nothing changed.", 2)
        return 0
    }
    ; the process, not the title — a window title can be a client's name
    Log("click-pick: got " id " — " WinGetProcessName("ahk_id " id))
    return AppFromWindow(id)
}

; Point at the box you type in. We get out of the way, you click it, and we
; keep where you clicked as a fraction of that window. Esc forgets it again.
GrabSpot(g, app) {
    global ClickSeen
    g.Hide()
    Sleep(250)
    TrayTip("Click where you type",
            "Click inside " app.name "'s text box. Esc to forget it.", 1)
    ClickSeen := false
    Hotkey("~LButton Up", NoteClick, "On")
    got := app.spot                                  ; wander off and nothing changes
    try {
        Loop 133 {                                   ; ~20 seconds, then give up
            Sleep(150)
            if GetKeyState("Escape", "P") {
                got := ""                            ; Esc is the only thing that clears it
                break
            }
            if !ClickSeen
                continue
            ClickSeen := false
            Sleep(200)                               ; let the click settle
            try {                                    ; it can close while we look at it
                CoordMode("Mouse", "Screen")
                MouseGetPos(&mx, &my, &win)
                ; It only counts if you clicked inside the app it's meant for.
                if (!win || !WinExist(app.match " ahk_id " win))
                    continue
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " win)
                if (ww < 1 || wh < 1)
                    continue
                got := Format("{:.4f},{:.4f}", (mx - wx) / ww, (my - wy) / wh)
                break
            }
        }
    }
    finally {
        Hotkey("~LButton Up", NoteClick, "Off")
        g.Show()                                     ; never leave the card hidden
    }
    return got
}

; Wait for you to click an app — taskbar, the window itself, or alt-tab.
; Returns the window you landed on, or 0 if you gave up or wandered off.
;
; A click always counts, even when it lands on the window that already had
; focus: hiding the settings box hands focus straight back to whatever was
; behind it, which is usually the very app you're about to click.
; Without a click we need the active window to have changed, otherwise focus
; drifting on its own (a notification, an app starting up) would count as a pick.
;
; ponytail: a 150ms poll to watch the active window, plus one temporary hotkey
; to catch the click. A click is over in a few milliseconds, so polling on its
; own walks straight past one — that was the bug.
global ClickSeen := false

NoteClick(*) {
    global ClickSeen
    ClickSeen := true
}

GrabNextWindow(start) {
    global ClickSeen
    me := DllCall("GetCurrentProcessId")
    ClickSeen := false
    Hotkey("~LButton Up", NoteClick, "On")     ; "~" = your click still gets through
    try {
        Loop 133 {                                       ; ~20 seconds, then give up
            Sleep(150)
            if GetKeyState("Escape", "P")
                return 0
            if (clicked := ClickSeen) {
                ClickSeen := false
                Sleep(350)                               ; let the window come up
            }
            if (id := WinActive("A")) && (clicked || id != start) && IsAppWindow(id, me)
                return id
        }
        return 0
    }
    finally
        Hotkey("~LButton Up", NoteClick, "Off")
}

; Is this a window you'd actually want to send something to? The taskbar, the
; desktop, the Start menu and our own windows are not apps.
IsAppWindow(id, me) {
    try {
        if (WinGetPID("ahk_id " id) = me)
            return false
        if (WinGetTitle("ahk_id " id) = "")              ; nameless helper windows
            return false
        cls := WinGetClass("ahk_id " id)
        if (cls ~= "^(Shell_TrayWnd|Shell_SecondaryTrayWnd"
                 . "|Progman|WorkerW|NotifyIconOverflowWindow"
                 . "|TaskListThumbnailWnd)$")
            return false
        exe := WinGetProcessName("ahk_id " id)
        if (exe ~= "i)^(StartMenuExperienceHost|SearchHost|ShellExperienceHost"
                 . "|TextInputHost)\.exe$")
            return false
        ; Explorer owns the taskbar, the desktop and a pile of invisible shell
        ; windows. Clicking a taskbar button can leave one of them briefly in
        ; front, and grabbing it gets you "ahk_exe explorer.exe" instead of the
        ; app you meant. A real folder window is the only one worth having.
        if (exe = "explorer.exe" && cls != "CabinetWClass")
            return false
        return true
    }
    return false                                         ; window vanished mid-check
}

; Everything you've got open right now, ready to be added. One entry per
; program — ten browser tabs are still one browser — most recent first,
; which is the order Windows hands its windows back in.
RunningApps() {
    me := DllCall("GetCurrentProcessId")
    seen := Map(), out := []
    DetectHiddenWindows(false)
    for id in WinGetList() {
        if !DllCall("IsWindowVisible", "ptr", id) || !IsAppWindow(id, me)
            continue
        try {
            exe := WinGetProcessName("ahk_id " id)
            if seen.Has(exe)
                continue
            seen[exe] := true
            out.Push(AppFacts(id, exe))
        }
    }
    return out
}

; Anything that would break a config.ini line, or turn it into a comment.
CleanName(s) => RegExReplace(Trim(s), "[=|;\[\]]", "-")

; What to call the app you clicked. Windows apps title their windows
; "Book1 - Excel" and "Google Flow - Aug 04, 05:42 PM - Opera", so the bit
; after the last dash is the app itself. Nothing after a dash? Use the exe.
NameFromWindow(title, exe) {
    bits := StrSplit(Trim(title), " - ")
    pick := (bits.Length > 1)               ; an empty title splits into nothing,
        ? Trim(bits[bits.Length])           ; so never reach into bits blind
        : ""
    return pick != "" ? pick : RegExReplace(exe, "i)\.exe$", "")
}

; Always the exe, browsers included. Pinning a browser to one tab's title
; meant it stopped matching the moment that tab's title changed — and what
; you want is the browser, showing whatever tab you're on.
MatchFor(name, exe) => "ahk_exe " exe

; Everything we can work out about a window on our own. Enter defaults to on
; because most things you send to are a chat box — flip it on the row if not.
AppFacts(id, exe := "") {
    if (exe = "")
        exe := WinGetProcessName("ahk_id " id)
    path := ""
    try path := WinGetProcessPath("ahk_id " id)     ; so we can reopen it later
    name := CleanName(NameFromWindow(WinGetTitle("ahk_id " id), exe))
    return { name: name, match: MatchFor(name, exe), launch: path, enter: "1",
             spot: "", exe: exe, title: WinGetTitle("ahk_id " id) }
}

AppFromWindow(id) => AppFacts(id)

; Renaming matters more than it looks. For a browser tab the name IS part of
; the window match, so changing it has to rebuild the match with it. Pull the
; exe back out of the old match rather than storing it twice.
RematchFor(name, oldMatch) {
    if !RegExMatch(oldMatch, "i)ahk_exe\s+(.+)$", &m)
        return name                         ; this one matched on title alone
    return MatchFor(name, Trim(m[1]))
}

; Never write what you copied into a file. The chip on screen shows you a
; preview because you're the one looking at it; a log gets emailed into bug
; reports, synced, and backed up. So the log gets the KIND of thing, never
; the thing. "Text: my bank password" becomes "Text".
Redact(label) => RegExReplace(label, "^([^:]+):.*$", "$1")

; Write a line to ai-snap.log when Debug=1 in config.ini.
Log(msg) {
    global Debug
    if (Debug = "1")
        try FileAppend(FormatTime(, "HH:mm:ss") "  " msg "`n", A_ScriptDir "\ai-snap.log")
}

; ============================================================================
;  themes — how the windows look. Pick one in Settings.
; ============================================================================
global ThemeNames := ["Claude Code", "Codex", "Gemini"]

; bg     = window     panel  = boxes and quiet buttons   accent = the Send button
; text   = writing    dim    = little grey hints         hot    = under the mouse
Themes() {
    return Map(
      "Claude Code", { bg: "262624", panel: "36352F", text: "F5F4EF",
                       dim: "A6A299", accent: "D97757", accentText: "FFFFFF",
                       panelHot: "45443C", accentHot: "E68A6C",
                       font: "Segoe UI" },
      "Codex",       { bg: "0D0D0D", panel: "1C1C1C", text: "ECECEC",
                       dim: "8E8E8E", accent: "10A37F", accentText: "FFFFFF",
                       panelHot: "2A2A2A", accentHot: "17B892",
                       font: "Consolas" },
      "Gemini",      { bg: "1B1C1D", panel: "2B2C2E", text: "E3E3E3",
                       dim: "9AA0A6", accent: "8AB4F8", accentText: "202124",
                       panelHot: "3A3B3E", accentHot: "A8C7FA",
                       font: "Google Sans" })   ; falls back to your system font
}

; The theme you picked, or the default if config.ini has something odd in it.
ThemeNow() {
    global Theme
    t := Themes()
    return t.Has(Theme) ? t[Theme] : t["Claude Code"]
}

; Dress a window: dark background, rounded corners, themed default font.
; +0x2000000 is WS_CLIPCHILDREN — don't paint the window background under the
; controls, which is half of why a card this busy used to flicker. (The other
; half was the hover watcher repainting everything; see HoverCheck.)
; Not WS_EX_COMPOSITED as well: it double-buffers, but it also drops children
; that overlap a sibling, and every row in the settings card sits on a panel.
ApplyTheme(g, t) {
    g.Opt("+0x2000000")
    g.BackColor := t.bg
    g.SetFont("s10 c" t.text, t.font)
    ; 20 = dark title bar (for windows that still have one)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "int", 20,
                "int*", 1, "int", 4)
    ; 33 = corner preference, 2 = rounded (Windows 11 rounds the whole card)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "int", 33,
                "int*", 2, "int", 4)
}

; Round off a control by clipping it to a rounded rectangle. Windows controls
; are square by nature, so this is what stops everything looking like 1998.
Round(ctrl, radius) {
    rc := Buffer(16)
    DllCall("GetClientRect", "ptr", ctrl.Hwnd, "ptr", rc)
    rgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0,
                   "int", NumGet(rc, 8, "int") + 1, "int", NumGet(rc, 12, "int") + 1,
                   "int", radius * 2, "int", radius * 2, "ptr")
    DllCall("SetWindowRgn", "ptr", ctrl.Hwnd, "ptr", rgn, "int", true)
}

; A flat, rounded, coloured button. Real Windows buttons ignore colour, so this
; is a Text control that behaves like one:
;   +0x200 centres the label vertically   +0x80 stops "&" underlining a letter
ThemeButton(g, t, label, opts, cb, primary := false) {
    bg  := primary ? t.accent     : t.panel
    hot := primary ? t.accentHot  : t.panelHot
    b := g.Add("Text", opts " Center +0x200 +0x80 Background" bg
             . " c" (primary ? t.accentText : t.text), label)
    b.OnEvent("Click", cb)
    Round(b, 8)
    Hover(b, bg, hot)
    return b
}

; ---- hover ------------------------------------------------------------------
; Static controls have no hover event, so one cheap timer watches what the
; mouse is over and recolours only when it moves onto something new.
global HoverBtns := [], HoverAt := 0

; NB: don't call that first colour "base" — in an object literal that word sets
; the prototype, and you get "Invalid base" instead of a button.
; Keep the raw hwnd: once a window is destroyed, asking the control object for
; its .Hwnd throws, so that number is the only safe way to check it's still there.
Hover(ctrl, cold, hot) {
    global HoverBtns
    HoverBtns.Push({ ctrl: ctrl, hwnd: ctrl.Hwnd, cold: cold, hot: hot })
    SetTimer(HoverCheck, 70)
}

HoverCheck() {
    global HoverBtns, HoverAt
    live := []
    for b in HoverBtns                    ; forget buttons whose window has gone
        if DllCall("IsWindow", "ptr", b.hwnd)
            live.Push(b)
    HoverBtns := live
    if !live.Length {                     ; nothing left to watch — stop ticking
        SetTimer(HoverCheck, 0)
        HoverAt := 0
        return
    }
    MouseGetPos(, , , &under, 2)          ; 2 = give me the control's hwnd
    if (under = HoverAt)
        return
    was := HoverAt, HoverAt := under
    for b in live {
        ; Only the one you've just left and the one you've just arrived at can
        ; have changed. Repainting all of them was a whole-card flash every
        ; time the pointer crossed anything, forty times over.
        if (b.hwnd != under && b.hwnd != was)
            continue
        try {
            b.ctrl.Opt("Background" (under = b.hwnd ? b.hot : b.cold))
            b.ctrl.Redraw()
        }
    }
}

; ============================================================================
;  the composer — a little box that holds everything you've grabbed so you can
;  type a note before it goes. Snips, highlighted text, whole pages: they all
;  stack up in here, in order, and go across in one message when you hit Send.
;
;  It's a plain AutoHotkey window, so it works no matter which program you
;  grabbed from — nothing is added to the app you're in.
; ============================================================================
; Take whatever is on the clipboard right now, park it in the composer, and
; bring the box up. ClipboardAll() keeps the *whole* clipboard — an image stays
; an image — so pasting it later is identical to pasting it now.
Attach(label, prev, wait) {
    global Comp, CompItems
    CompItems.Push(it := { label: label, data: ClipboardAll(), wait: wait })
    Log("attached: " Redact(label) " (" it.data.Size " bytes)")
    UpdateTrayTip()
    if Comp
        RebuildComposer()             ; already open — redraw it with the new chip
    else
        ShowComposer(prev)
}

; There's no title bar to grab, so dragging the heading moves the card.
; 0xA1 = "act like the mouse went down on the caption", 2 = the caption.
DragCard(wParam, lParam, msg, hwnd) {
    global Comp, CompHead, SetGui, SetHead, Badge
    ; The floating button does its own thing — it has to tell a click from a
    ; drag from a triple-click, which the caption trick below can't.
    if (Badge && hwnd = Badge.Hwnd) {
        ; Windows sends the SECOND click of a double as its own message, once
        ; it has decided the two were close enough in time and place. That's
        ; the real double-click detector, and it means the second click never
        ; arrives as an ordinary one — which is why counting them alone
        ; silently never saw a double at all.
        if (msg = 0x203)                       ; WM_LBUTTONDBLCLK
            BadgeDoubled()
        else
            BadgeDown()
        return 0
    }
    if (Comp && CompHead && hwnd = CompHead.Hwnd)
        PostMessage(0xA1, 2, 0, , "ahk_id " Comp.Hwnd)
    else if (SetGui && SetHead && hwnd = SetHead.Hwnd)
        PostMessage(0xA1, 2, 0, , "ahk_id " SetGui.Hwnd)
}

; Open the box, or just bring it back to the front if it's already open.
; Anything stored earlier is still in there — the grabs and your note both.
; No title bar: it's a plain rounded card you drag by its heading.
ShowComposer(prev) {
    global Comp, CompItems, CompPrev, CompNote, CompEdit, CompHead
    if Comp {
        Comp.Show()
        return
    }
    CompPrev := prev
    t := ThemeNow()
    Comp := g := Gui("-Caption +AlwaysOnTop +ToolWindow", "Send to AI")
    g.MarginX := 18, g.MarginY := 16
    ApplyTheme(g, t)

    g.SetFont("s11 w600 c" t.text)
    CompHead := g.Add("Text", "xm ym w360 +0x100", "Send to AI")   ; 0x100 = clickable
    g.SetFont("s12 c" t.dim)
    g.Add("Text", "x+0 yp-2 w32 h28 Center +0x200 +0x100 Background" t.bg, "✕")
        .OnEvent("Click", StoreComposer)

    ; --- what you've grabbed, one rounded chip each ---
    g.SetFont("s9 c" t.dim)
    if !CompItems.Length
        g.Add("Text", "xm y+14 w392", "Nothing grabbed yet.")
    g.SetFont("s10 c" t.text)
    for i, it in CompItems {
        chip := g.Add("Text", (i = 1 ? "xm y+12" : "xm y+8")
                    . " w352 h36 +0x200 +0x80 +0x4000 Background" t.panel
                    . " c" t.text, "  " it.label)
        Round(chip, 10)
        x := g.Add("Text", "x+8 yp w32 h36 Center +0x200 Background" t.panel
                         . " c" t.dim, "✕")
        x.OnEvent("Click", Remover(i))          ; drop just this one
        Round(x, 10)
        Hover(x, t.panel, t.panelHot)
    }

    ; --- your note ---
    g.SetFont("s9 c" t.dim)
    g.Add("Text", "xm y+16 w392", "Add a note  ·  Enter sends  ·  Shift+Enter = new line")
    g.SetFont("s10 c" t.text)
    CompEdit := g.Add("Edit", "xm y+8 w392 h108 -E0x200 -VScroll +Multi +WantReturn"
                            . " Background" t.panel " c" t.text)
    CompEdit.Value := CompNote                  ; whatever you'd typed before
    Round(CompEdit, 10)

    ThemeButton(g, t, "Send",   "xm y+16 w124 h40", ComposerSend, true)
    ThemeButton(g, t, "Store",  "x+10 w124 h40",    StoreComposer)
    ThemeButton(g, t, "Cancel", "x+10 w124 h40",    CancelComposer)

    g.OnEvent("Escape", StoreComposer)           ; Esc never loses your stuff
    g.OnEvent("Close",  StoreComposer)

    g.Show()
    CompEdit.Focus()                  ; land in the note box, ready to type
}

; Adding or dropping a grab changes how tall the card is, so the simplest
; thing that works is to build it again — your note comes along with it.
RebuildComposer() {
    global Comp, CompPrev, CompNote, CompEdit
    if !Comp
        return
    CompNote := CompEdit.Value
    prev := CompPrev
    Comp.Destroy()
    Comp := 0
    ShowComposer(prev)
}

; One remover per chip. It's a function so each ✕ keeps its own number —
; a closure made inside the loop would share the last one.
Remover(i) => (*) => RemoveAttachment(i)

RemoveAttachment(i) {
    global CompItems
    if (i <= CompItems.Length)
        CompItems.RemoveAt(i)
    UpdateTrayTip()
    RebuildComposer()
}

; Send the lot: each attachment in the order you grabbed it, then your note,
; then Enter. Restoring each saved clipboard and pasting is what lets one
; message carry an image, some copied text and your own typing together.
ComposerSend(*) {
    global Comp, CompItems, CompPrev, CompNote, CompEdit
    if !Comp
        return
    note  := CompEdit.Value
    items := CompItems
    prev  := CompPrev
    CompNote := ""
    CloseComposer()                   ; get our window out of the way first
    if (!items.Length && Trim(note) = "")
        return
    if !FocusTarget() {
        ; Couldn't get to the app, so nothing was sent — put everything back
        ; rather than quietly binning what you spent a minute collecting.
        CompItems := items, CompNote := note
        UpdateTrayTip()
        ShowComposer(prev)
        return
    }
    ClipHold()                        ; every line below changes the clipboard,
    try {                             ; and none of them are for fill mode
        stolen := false
        for it in items {
            A_Clipboard := it.data    ; put that exact grab back on the clipboard
            ; Wait for it to actually land. A fixed sleep was a race, and losing
            ; it meant Ctrl+V arrived at an empty clipboard — which is where the
            ; "Nothing to paste from the clipboard" toasts came from.
            if !ClipWait(4, 1) {      ; 1 = images count as something
                Log("clipboard never came back for: " Redact(it.label))
                continue
            }
            if !Paste() {             ; something jumped in front mid-send
                stolen := true
                break
            }
            Sleep(it.wait)            ; images especially need a moment to attach
        }
        if (!stolen && Trim(note) != "") {
            A_Clipboard := note
            if (ClipWait(4, 1) && !Paste())
                stolen := true
            else
                Sleep(120)
        }
        if stolen {
            ; Half a message is worse than none — leave the rest unsent and
            ; hand it all back rather than firing Enter on a partial one.
            CompItems := items, CompNote := note
            UpdateTrayTip()
            TrayTip("Send stopped", "Something else took focus. Nothing was sent"
                  . " on, and your grabs are still here.", 2)
            ShowComposer(prev)
            return
        }
        if EnterOK() {                ; you clicked Send, so we always send —
            Send("{Enter}")           ; unless it's Word and Enter means nothing
            Sleep(80)
        }
    }
    finally
        ClipRelease()
    GoBack(prev)
}

; Put it away without sending. Nothing is lost — the list and your note sit
; there until you grab something else, and the box comes back with the lot.
StoreComposer(*) {
    global Comp, CompItems, CompPrev, CompNote, CompEdit
    if !Comp
        return
    CompNote := CompEdit.Value
    prev := CompPrev
    Comp.Destroy()
    Comp := 0
    Log("stored — " CompItems.Length " item(s) waiting")
    UpdateTrayTip()
    if CompItems.Length
        TrayTip("Stored for later",
                CompItems.Length " waiting. Grab more, then hit Send.", 1)
    GoBack(prev)
}

; Throw the whole lot away.
CancelComposer(*) {
    global CompPrev
    prev := CompPrev
    Log("composer cancelled")
    CloseComposer()
    GoBack(prev)
}

CloseComposer() {
    global Comp, CompItems, CompPrev, CompNote
    if Comp
        Comp.Destroy()
    Comp := 0, CompItems := [], CompPrev := 0, CompNote := ""
    UpdateTrayTip()
}

; Tray tooltip doubles as the "you've got stuff waiting" reminder.
UpdateTrayTip() {
    global Active, CompItems
    A_IconTip := "AI Snap  —  sending to: " Active
        . (CompItems.Length ? "`n" CompItems.Length " waiting to send" : "")
}

; Squash text down to one short line so it reads nicely in the list.
Preview(t) {
    t := RegExReplace(Trim(t), "\s+", " ")
    return StrLen(t) > 45 ? SubStr(t, 1, 45) "…" : t
}

; ============================================================================
;  the floating button — a small round thing that sits on top of everything
;
;  Click it to open settings, click it again to put them away. Drag it
;  wherever you want it and it stays there. Double-click gets rid of it, and
;  the tray menu brings it back.
;
;  Click and drag start the same way, so we can't know which one it was until
;  the button comes back up: moved = you were dragging, didn't = you clicked.
; ============================================================================
ShowBadge() {
    global Badge, cfg
    if Badge
        return
    t := ThemeNow()
    ; E0x8000000 = never takes focus. E0x80000 = layered, and that one is what
    ; makes the circle a circle: clipping a window to a round region keeps or
    ; drops whole pixels, so the rim comes out as visible stair-steps. A
    ; layered window is painted from a bitmap that carries its own alpha, so
    ; the edge can fade instead of jumping.
    Badge := g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x8000000 +E0x80000",
                      "AI Snap button")
    g.MarginX := 0, g.MarginY := 0
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "int", 2,
                "int*", 1, "int", 4)       ; no square shadow behind it
    ; Where you last left it, or out of the way at the bottom right.
    x := IniRead(cfg, "Look", "BadgeX", A_ScreenWidth - 96)
    y := IniRead(cfg, "Look", "BadgeY", A_ScreenHeight - 152)
    g.Show("NoActivate x" OnScreen(x, 48, A_ScreenWidth)
                  . " y" OnScreen(y, 48, A_ScreenHeight) " w48 h48")
    PaintCircle(g.Hwnd, 48, "0xFF" t.accent, "0xFF" t.accentText, "AI", t.font)
}

; Draw an anti-aliased filled circle with a label into an ARGB bitmap and hand
; that to the window. Every pixel carries its own transparency, so the rim
; fades rather than steps — and the corners outside the circle are completely
; clear, which also means clicks out there fall through to whatever is behind.
PaintCircle(hwnd, size, fill, ink, label, font) {
    static token := 0
    if !token {
        si := Buffer(24, 0)
        NumPut("uint", 1, si, 0)
        DllCall("gdiplus\GdiplusStartup", "ptr*", &token, "ptr", si, "ptr", 0)
    }
    ; a 32-bit top-down bitmap to draw into
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", size, bi, 4)
    NumPut("int", -size, bi, 8), NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    dc  := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    bmp := DllCall("CreateDIBSection", "ptr", dc, "ptr", bi, "uint", 0,
                   "ptr*", &bits := 0, "ptr", 0, "uint", 0, "ptr")
    old := DllCall("SelectObject", "ptr", dc, "ptr", bmp, "ptr")

    DllCall("gdiplus\GdipCreateFromHDC", "ptr", dc, "ptr*", &gfx := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gfx, "int", 4)     ; antialias
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", gfx, "int", 4)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", Integer(fill), "ptr*", &brush := 0)
    ; inset half a pixel so the edge sits inside the bitmap and has room to fade
    DllCall("gdiplus\GdipFillEllipse", "ptr", gfx, "ptr", brush,
            "float", 0.5, "float", 0.5, "float", size - 1.0, "float", size - 1.0)

    DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", font, "ptr", 0,
            "ptr*", &fam := 0)
    if fam {
        DllCall("gdiplus\GdipCreateFont", "ptr", fam, "float", size / 3.2,
                "int", 1, "int", 2, "ptr*", &fnt := 0)         ; bold, in pixels
        DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "ushort", 0,
                "ptr*", &fmt := 0)
        DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmt, "int", 1)
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", fmt, "int", 1)
        DllCall("gdiplus\GdipCreateSolidFill", "uint", Integer(ink), "ptr*", &tb := 0)
        box := Buffer(16, 0)
        NumPut("float", size, box, 8), NumPut("float", size, box, 12)
        DllCall("gdiplus\GdipDrawString", "ptr", gfx, "wstr", label, "int", -1,
                "ptr", fnt, "ptr", box, "ptr", fmt, "ptr", tb)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", tb)
        DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
        DllCall("gdiplus\GdipDeleteFont", "ptr", fnt)
        DllCall("gdiplus\GdipDeleteFontFamily", "ptr", fam)
    }

    sz := Buffer(8, 0)
    NumPut("int", size, sz, 0), NumPut("int", size, sz, 4)
    blend := Buffer(4, 0)
    NumPut("uchar", 255, blend, 2), NumPut("uchar", 1, blend, 3)   ; AC_SRC_ALPHA
    ; a null destination point leaves the window where it is; 2 = ULW_ALPHA
    DllCall("UpdateLayeredWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "ptr", sz,
            "ptr", dc, "ptr", Buffer(8, 0), "uint", 0, "ptr", blend, "uint", 2)

    DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gfx)
    DllCall("SelectObject", "ptr", dc, "ptr", old)
    DllCall("DeleteObject", "ptr", bmp)
    DllCall("DeleteDC", "ptr", dc)
}

; A saved position is only as good as the monitor it was saved on — unplug a
; screen and it would sit somewhere you can't reach or click.
OnScreen(v, size, limit) => !IsInteger(v) ? 0 : Min(limit - size, Max(0, v + 0))

HideBadge(remember := false) {
    global Badge, BadgeWait, cfg
    BadgeWait := false
    SetTimer(BadgeClicked, 0)
    if Badge {
        try Badge.Destroy()
        Badge := 0
    }
    if remember {
        IniWrite("0", cfg, "Look", "Button")
        TrayTip("Button put away", "Tray icon → Show the floating button.", 1)
    }
}

ToggleBadge() {
    global Badge, cfg
    if Badge
        HideBadge(true)
    else {
        IniWrite("1", cfg, "Look", "Button")
        ShowBadge()
    }
}

; --- press, move, release ----------------------------------------------------
BadgeDown() {
    global BadgeFrom, BadgeMoved, Badge
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    WinGetPos(&wx, &wy, , , "ahk_id " Badge.Hwnd)
    BadgeFrom := [mx, my, wx, wy]
    BadgeMoved := false
    SetTimer(BadgeDrag, 15)
}

BadgeDrag() {
    global BadgeFrom, BadgeMoved, Badge
    if !GetKeyState("LButton", "P") {          ; you let go
        SetTimer(BadgeDrag, 0)
        BadgeUp()
        return
    }
    if !Badge {
        SetTimer(BadgeDrag, 0)
        return
    }
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    ; A few pixels of wobble while clicking isn't a drag.
    if (!BadgeMoved && Abs(mx - BadgeFrom[1]) + Abs(my - BadgeFrom[2]) < 6)
        return
    BadgeMoved := true
    Badge.Move(BadgeFrom[3] + mx - BadgeFrom[1], BadgeFrom[4] + my - BadgeFrom[2])
}

; What counts as a double-click is a thing Windows already knows, because the
; user set it in Mouse settings: how long you get between the two, and how far
; the pointer may drift. Ask it rather than inventing numbers — someone who
; set a slow double-click gets their slow double-click.
;   36 = SM_CXDOUBLECLK, 37 = SM_CYDOUBLECLK
DoubleTime()  => DllCall("GetDoubleClickTime", "uint")
DoubleSlop(i) => DllCall("GetSystemMetrics", "int", i)

; Two clicks are a double-click only if they were BOTH quick enough and close
; enough together. That second half is what stops one fast click, or two
; separate clicks either side of the button, being read as a double.
IsDoubleClick(gap, dx, dy) =>
    gap <= DoubleTime() && dx <= DoubleSlop(36) && dy <= DoubleSlop(37)

BadgeUp() {
    global Badge, BadgeMoved, BadgeWait, BadgeLast, BadgeAt, cfg
    if BadgeMoved {                            ; you were moving it — remember where
        BadgeWait := false
        SetTimer(BadgeClicked, 0)
        try {
            WinGetPos(&x, &y, , , "ahk_id " Badge.Hwnd)
            IniWrite(x, cfg, "Look", "BadgeX")
            IniWrite(y, cfg, "Look", "BadgeY")
        }
        return
    }
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    if (BadgeWait && IsDoubleClick(A_TickCount - BadgeLast,
                                   Abs(mx - BadgeAt[1]), Abs(my - BadgeAt[2]))) {
        BadgeWait := false
        SetTimer(BadgeClicked, 0)              ; the single click never happens
        HideBadge(true)                        ; that was a double — off it goes
        return
    }
    ; Might be the first of two. Hold the single-click action until the window
    ; for a second one has passed, so a double never opens settings on the way.
    BadgeWait := true, BadgeLast := A_TickCount, BadgeAt := [mx, my]
    SetTimer(BadgeClicked, -(DoubleTime() + 40))
}

; Windows has already applied the user's own double-click speed and slop, so
; there's nothing left to check — call off the pending single click and go.
BadgeDoubled() {
    global BadgeWait
    BadgeWait := false
    SetTimer(BadgeClicked, 0)
    HideBadge(true)
}

BadgeClicked() {
    global BadgeWait, SetGui
    if !BadgeWait                              ; a double already claimed it
        return
    BadgeWait := false
    SetGui ? CloseSettings() : ShowSettings()  ; open already? then close it
}

; ============================================================================
;  first run — a short hello, once
;
;  Nothing about this app is visible until you press a key, so without this
;  the first run is a tray icon and no idea what to do with it. Shown once,
;  then never again: [Behavior] Welcomed in config.ini.
; ============================================================================
ShowWelcome() {
    global cfg
    t := ThemeNow()
    g := Gui("-Caption +AlwaysOnTop +ToolWindow", "AI Snap welcome")
    g.MarginX := 26, g.MarginY := 24
    ApplyTheme(g, t)

    g.SetFont("s15 w700 c" t.accent, t.font)
    g.Add("Text", "xm ym w400", "AI Snap is running")
    g.SetFont("s9 c" t.dim)
    g.Add("Text", "xm y+4 w400", "Three keys, and they work in any program.")

    g.SetFont("s10 c" t.text)
    Step("Alt + 2", "Drag a box on screen — it goes to your AI")
    Step("Alt + 3", "Sends whatever text you've highlighted")
    Step("Alt + 9", "Filling — every copy lands in the next cell")

    g.SetFont("s9 c" t.dim)
    g.Add("Text", "xm y+18 w400",
          "Grab something and a small box opens. Type a note, grab more if you"
        . " like, then hit Enter — it all arrives as one message.")
    g.Add("Text", "xm y+12 w400",
          "Click the tray icon whenever you want to change any of this.")

    g.SetFont("s10 c" t.text)
    ThemeButton(g, t, "Show me the settings", "xm y+22 w194 h40", Both, true)
    ThemeButton(g, t, "Got it", "x+12 w194 h40", Done)
    g.OnEvent("Escape", Done)
    g.OnEvent("Close",  Done)
    g.Show()

    Step(key, what) {
        p := g.Add("Text", "xm y+12 w96 h32 Center +0x200 +0x80 Background" t.panel
                 . " c" t.text, key)
        Round(p, 9)
        g.Add("Text", "x+12 yp w292 h32 +0x200", what)
    }
    Done(*) {
        try IniWrite("1", cfg, "Behavior", "Welcomed")
        g.Destroy()
    }
    Both(*) {
        Done()
        ShowSettings()
    }
}

; ============================================================================
;  settings — one card. Your apps live at the top as a list you can add to,
;  remove from and pick from; keys and options sit underneath.
;
;  Adding or removing an app changes how tall the card is, so the same trick
;  the composer uses applies here: throw the window away and build it again,
;  carrying anything you'd already typed across in SetPend.
; ============================================================================
global SetGui  := 0        ; the settings window while it's open
global SetHead := 0        ; its heading, which you drag the card by
global SetCtl  := Map()    ; the one free-text box, so we can read it back
global SetPend := Map()    ; every setting as it stands, saved or not
global SetTheme := ""      ; the theme as saved, while you try others on
global SetFresh := false   ; just added an app — put the cursor in its name
global SetPage  := "Send to"   ; which sidebar page you're looking at

TurnTo(page) {
    global SetPage
    SetPage := page
    RefreshSettings()
}

; Everything editable in one Map, loaded once when the card first opens.
; Clicking a pill just changes a value in here and rebuilds, so what you see
; is always what would be saved — including the theme, which repaints live.
SettingsState() {
    global SetPend, cfg, Active, Theme
    if SetPend.Count
        return
    SetPend["target"]  := Active
    SetPend["theme"]   := Theme
    SetPend["dict"]    := IniRead(cfg, "Hotkeys",   "Dictate",       "!1")
    SetPend["snip"]    := IniRead(cfg, "Hotkeys",   "SnipAndSend",   "!2")
    SetPend["sel"]     := IniRead(cfg, "Hotkeys",   "CopySelection", "!3")
    SetPend["all"]     := IniRead(cfg, "Hotkeys",   "CopyAllOnPage", "!4")
    SetPend["post"]    := IniRead(cfg, "Hotkeys",   "Post",          "!0")
    SetPend["fill"]        := IniRead(cfg, "Hotkeys",   "Fill",          "!9")
    SetPend["dictkey"]     := IniRead(cfg, "Dictation", "Key",           "F4")
    SetPend["comp"]        := IniRead(cfg, "Behavior",  "Composer",      "1")
    SetPend["auto"]        := IniRead(cfg, "Behavior",  "AutoSend",      "1")
    SetPend["restore"]     := IniRead(cfg, "Behavior",  "RestoreFocus",  "1")
    SetPend["advance"]     := IniRead(cfg, "Fill",      "Advance",       "Tab")
    SetPend["filltimeout"] := IniRead(cfg, "Fill",      "Timeout",       "120")
}

; Build the card again with the list as it is now, keeping your unsaved edits.
RefreshSettings() {
    global SetCtl, SetPend
    CommitRename()
    for key, c in SetCtl {                      ; the free-text boxes aren't
        if (key != "rename")                    ; pills, so their values have
            try SetPend[key] := c.Value         ; to be rescued by hand
    }
    ShowSettings()
}

; The selected app's name sits in an Edit right in the list, so it can be
; fixed where you're looking at it. Clicking anything else commits it; Esc
; walks away from it. Saved to config.ini at once, same as adding one.
CommitRename() {
    global SetCtl, SetPend, Apps, cfg, Active
    if !SetCtl.Has("rename")
        return
    want := ""
    try want := CleanName(SetCtl["rename"].Value)
    was := SetPend["target"]
    if (want = "" || want = was)
        return
    for a in Apps
        if (a.name = want)                      ; that name's taken — leave it
            return
    for a in Apps {
        if (a.name != was)
            continue
        IniDelete(cfg, "Apps", was)
        a.match := RematchFor(want, a.match)
        a.name  := want
        IniWrite(AppLine(a), cfg, "Apps", want)
        if (Active = was) {
            Active := want
            IniWrite(want, cfg, "Target", "Active")
        }
        SetPend["target"] := want
        Log("renamed " was " → " want " (" a.match ")")
        return
    }
}

; Shut it and forget the unsaved edits, so next time reflects config.ini.
; That includes the theme: previewing one paints the real windows, so backing
; out has to put the saved one back or the composer keeps the colours you
; didn't choose.
CloseSettings() {
    global SetGui, SetPend, SetCtl, SetTheme, Theme
    if SetGui
        try SetGui.Destroy()
    if (SetTheme != "")
        Theme := SetTheme
    SetGui := 0, SetPend := Map(), SetCtl := Map(), SetTheme := ""
}

SetOne(key, val) {
    global SetPend
    SetPend[key] := val
    RefreshSettings()
}

; "!1" reads as "Alt + 1" to anyone who doesn't write AutoHotkey for fun.
Pretty(hk) {
    out := ""
    for pair in [["^", "Ctrl"], ["!", "Alt"], ["+", "Shift"], ["#", "Win"]] {
        if InStr(hk, pair[1]) {
            out .= pair[2] " + "
            hk := StrReplace(hk, pair[1])
        }
    }
    return out StrUpper(hk)
}

; Ask for a key combo. AHK has a Hotkey control that does this in one line,
; but it's a white box that refuses every colour option, and one white box in
; a dark card looks like a bug. So: a little card, and the next key wins.
CaptureCombo(label) {
    global SetGui
    t := ThemeNow()
    c := Gui("-Caption +AlwaysOnTop +ToolWindow" (SetGui ? " +Owner" SetGui.Hwnd : ""))
    c.MarginX := 24, c.MarginY := 22
    ApplyTheme(c, t)
    c.SetFont("s11 w600 c" t.text)
    c.Add("Text", "xm ym w300 Center", label)
    c.SetFont("s9 c" t.dim)
    c.Add("Text", "xm y+12 w300 Center", "Press the keys you want.`nEsc keeps the old one.")
    c.Show()

    ih := InputHook()
    ih.KeyOpt("{All}", "E")                     ; any key ends the wait...
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-E")
    ih.Start()                                  ; ...except the modifiers
    ih.Wait(20)
    mods := (GetKeyState("Ctrl",  "P") ? "^" : "")   ; read while still held
          . (GetKeyState("Alt",   "P") ? "!" : "")
          . (GetKeyState("Shift", "P") ? "+" : "")
          . ((GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) ? "#" : "")
    key := ih.EndKey
    c.Destroy()
    if (ih.EndReason != "EndKey" || key = "Escape")
        return ""
    ; A bare key would be swallowed everywhere, in every program, forever.
    ; Enter as your send key means you can never type Enter again.
    if (mods = "") {
        MsgBox("Hold Ctrl, Alt, Shift or the Windows key with it.`n`n"
             . "On its own, " key " would stop working everywhere else.",
               "AI Snap", "Iconi 4096")
        return ""
    }
    return mods key
}

Rebind(key, label) {
    if (combo := CaptureCombo(label))
        SetOne(key, combo)
}

ShowSettings(*) {
    global cfg, Apps, Theme, ThemeNames, SetPage, Filling
    global SetGui, SetHead, SetCtl, SetPend, SetTheme, SetFresh
    SettingsState()
    ; Keep the old window up while the new one is built, then swap. Destroying
    ; first leaves a hole on screen for as long as the rebuild takes, and since
    ; every click in here rebuilds, that hole is what made it flash.
    old := SetGui, ox := "", oy := ""
    if old {
        try WinGetPos(&ox, &oy, , , "ahk_id " old.Hwnd)
    }
    SetCtl := Map()
    if (SetTheme = "")                        ; remember the saved one first,
        SetTheme := Theme                     ; Cancel has to be able to undo this
    Theme := SetPend["theme"]                 ; so the card repaints as you pick
    t := ThemeNow()

    ; A sidebar down the left, one page at a time on the right. Everything
    ; lines up to these and nothing anywhere else invents its own number.
    SIDE := 172                               ; sidebar width
    CX   := SIDE + 26                         ; where content starts
    CW   := 452                               ; and how wide it is
    RowH := 46                                ; one row in a card
    PAGES := ["Send to", "Keys", "Filling", "Options"]
    cardTop := 0, cardRow := 0, cardN := 0    ; the card the rows are landing in

    ; Every page is the height of the tallest one, so moving between them
    ; doesn't resize the window out from under your cursor. Only "Send to"
    ; and "Keys" can be the tallest — the other two are always shorter.
    picked := false
    for a in Apps
        picked := picked || (a.name = SetPend["target"])
    appsH := 30 + ((Apps.Length + 1) * RowH + 8) + 14 + 38 + 16
           + (picked ? (2 * RowH + 8) + 14 : 0)
    keysH := 16 + (6 * RowH + 8) + 14 + (RowH + 8) + 14
    WH := 52 + Max(appsH, keysH) + 68          ; header + content + save row

    SetGui := g := Gui("-Caption +AlwaysOnTop +ToolWindow", "AI Snap settings")
    g.MarginX := 0, g.MarginY := 0
    ApplyTheme(g, t)

    ; ---- sidebar -----------------------------------------------------------
    g.SetFont("s14 w700 c" t.accent, t.font)
    SetHead := g.Add("Text", "x24 y22 w" (SIDE - 40) " +0x100", "AI Snap")
    g.SetFont("s8 c" t.dim)
    g.Add("Text", "x24 y+2 w" (SIDE - 40), "snip · copy · send")

    y := 74
    for i, name in PAGES {
        on := (SetPage = name)
        nav := g.Add("Text", "x12 y" (y += 34) " w" (SIDE - 24) " h34 +0x200 +0x80"
                   . " Background" (on ? t.panel : t.bg)
                   . " c" (on ? t.text : t.dim), "    " name)
        nav.OnEvent("Click", Pager(name))
        Round(nav, 9)
        if !on
            Hover(nav, t.bg, t.panel)
    }

    ; ---- the page ----------------------------------------------------------
    g.SetFont("s11 w600 c" t.text)
    g.Add("Text", "x" CX " y24 w" (CW - 40), StrUpper(SetPage))
    g.SetFont("s8 c" t.dim)
    cy := 52                                  ; running y for the content column

    if (SetPage = "Send to")
        PageApps()
    else if (SetPage = "Keys")
        PageKeys()
    else if (SetPage = "Filling")
        PageFill()
    else
        PageOptions()

    ; ---- save --------------------------------------------------------------
    ; Pinned to the bottom of the fixed height, not to wherever the page ended.
    sy := WH - 56
    ThemeButton(g, t, "Save and reload", "x" CX " y" sy " w" (CW - 132) " h40", Save, true)
    ThemeButton(g, t, "Cancel", "x+8 w124 h40", (*) => CloseSettings())
    g.SetFont("s12 c" t.dim)
    g.Add("Text", "x" (CX + CW - 30) " y20 w30 h28 Center +0x200 +0x100 Background" t.bg, "✕")
        .OnEvent("Click", (*) => CloseSettings())

    g.OnEvent("Escape", (*) => CloseSettings())
    g.OnEvent("Close",  (*) => CloseSettings())
    g.Show((ox = "" ? "" : "x" ox " y" oy " ") "w" (CX + CW + 26) " h" WH)
    if old {
        try old.Destroy()                 ; the new one is already covering it
    }
    ; Just added one? Land in its name box with the text selected, so a page
    ; title that came out too long can be typed over straight away.
    if (SetFresh && SetCtl.Has("rename")) {
        SetCtl["rename"].Focus()
        PostMessage(0xB1, 0, -1, SetCtl["rename"])       ; EM_SETSEL = select all
    }
    SetFresh := false
    Log("settings card built — page " SetPage)

    ; ---- the pages ---------------------------------------------------------
    PageApps() {
        Note("Click one to send there. Auto follows whichever you used last.")
        Card(Apps.Length + 1)
        AppRow("Auto", "whichever app I used last", "Auto")
        for i, a in Apps
            AppRow(a.name, a.match, a.name, i, a.enter)
        g.SetFont("s10 c" t.text)
        ThemeButton(g, t, "Running apps", "x" CX " y" cy " w" (CW // 3 - 6) " h38",
                    (*) => ShowRunningApps())
        ThemeButton(g, t, "Click an app", "x+8 yp w" (CW // 3 - 6) " h38", PickByClick)
        ThemeButton(g, t, "Browse…",      "x+8 yp w" (CW // 3 - 6) " h38", PickByBrowse)
        cy += 38 + 16

        ; Whichever one you've selected gets its own card: the name where you
        ; can fix it, and the spot it should click before typing.
        for i, a in Apps {
            if (a.name != SetPend["target"])
                continue
            Card(2)
            y := RowTop()
            Label(y, "Name")
            SetCtl["rename"] := ed := g.Add("Edit",
                "x" (CX + CW - 232) " y" (y + 10) " w216 h26 -E0x200 Background"
                . t.panelHot " c" t.text, a.name)
            Round(ed, 8)
            y := RowTop()
            Label(y, "Where to type")
            Pill("x" (CX + CW - 176) " y" (y + 8) " w160 h30 Center",
                 a.spot != "" ? "pointed ✓" : "point at it", a.spot != "",
                 Spotter(i), a.spot = "")
            break
        }
    }

    PageKeys() {
        Note("Click a key to change it. Hold Ctrl, Alt, Shift or Win with it.")
        Card(6)
        KeyRow("Talk to my AI",        "dict")
        KeyRow("Snip a screenshot",    "snip")
        KeyRow("Send my highlight",    "sel")
        KeyRow("Select all and send",  "all")
        KeyRow("Send by hand",         "post")
        KeyRow("Start filling",        "fill")
        Card(1)
        SetCtl["dictkey"] := ed := CardEdit("Push-to-talk key", SetPend["dictkey"],
                                            "the one your dictation app uses")
    }

    PageFill() {
        Note("Turn it on and just copy. Every copy lands in your app and moves "
           . "to the next cell. It stays on until you turn it off.")
        Card(1)
        LiveSwitch(Filling ? "On — every copy is landing" : "Off",
                   Filling, (*) => ToggleFill())
        Card(2)
        CardSegment("Then press", "advance", ["Tab", "Enter", "Down", "None"])
        SetCtl["filltimeout"] := CardEdit("Give up after", SetPend["filltimeout"],
                                          "seconds with nothing copied · 0 = never")
    }

    PageOptions() {
        Note("")
        Card(3)
        CardSwitch("Ask me for a note first", "comp")
        CardSwitch("Send automatically",      "auto")
        CardSwitch("Come back to my window",  "restore")
        Card(1)
        CardSegment("Theme", "theme", ThemeNames)
    }

    ; ---- the pieces a page is built from -----------------------------------
    Note(text) {
        if (text != "") {
            g.SetFont("s8 c" t.dim)
            h := StrLen(text) > 70 ? 30 : 16
            g.Add("Text", "x" CX " y" cy " w" CW " h" h, text)
            cy += h + 8
        }
        g.SetFont("s10 c" t.text)
    }

    ; The panel a group of rows sits inside. Drawn first, at the height its
    ; rows will need, so the rows land on top of it — later controls are the
    ; ones on top in a Gui, which is the only stacking we get.
    Card(rows) {
        cardTop := cy, cardRow := 0, cardN := rows
        panel := g.Add("Text", "x" CX " y" cy " w" CW " h" (rows * RowH + 8)
                     . " Background" t.panel)
        Round(panel, 14)
        cy += rows * RowH + 8 + 14            ; where the next thing starts
    }

    ; Where the next row goes, and a hairline under it unless it's the last.
    RowTop() {
        y := cardTop + 4 + cardRow * RowH
        cardRow++
        if (cardRow < cardN)
            g.Add("Text", "x" (CX + 16) " y" (y + RowH - 1) " w" (CW - 32) " h1"
                . " Background" t.panelHot)
        return y
    }

    ; A flat, rounded pill. Accent when it's the one that's on.
    Pill(opts, label, on, cb, quiet := false) {
        p := g.Add("Text", opts " +0x200 +0x80 Background" (on ? t.accent : t.panelHot)
                 . " c" (on ? t.accentText : (quiet ? t.dim : t.text)), label)
        p.OnEvent("Click", cb)
        Round(p, 9)
        if !on
            Hover(p, t.panelHot, t.panel)
        return p
    }

    ; An iOS-style switch: a rounded track with a round knob parked at one end.
    ; Two controls, because a Windows checkbox will not be talked into this.
    ; One control, not two. A knob drawn as a second control on top of the
    ; track is a sibling overlapping a sibling, and that is exactly what this
    ; window can't do — so the knob is a character shoved to one end instead.
    OnOff(x, y, on, cb) {
        g.SetFont("s13 c" (on ? t.accentText : t.dim))
        sw := g.Add("Text", "x" x " y" (y + 11) " w48 h24 +0x200 +0x80 "
                  . (on ? "Right" : "Left")
                  . " Background" (on ? t.accent : t.panelHot), on ? "●  " : "  ●")
        sw.OnEvent("Click", cb)
        Round(sw, 12)
        if !on
            Hover(sw, t.panelHot, t.panel)
        g.SetFont("s10 c" t.text)
    }

    ; Anything sitting on a card has to be painted the card's colour. A Text
    ; control with no Background of its own paints the WINDOW's, which shows
    ; up as a darker block punched through the panel.
    Label(y, text, wide := 0) {
        g.SetFont("s10 c" t.text)
        g.Add("Text", "x" (CX + 16) " y" y " w" (wide ? wide : CW - 200) " h" RowH
            . " +0x200 Background" t.panel, text)
    }

    CardSwitch(text, key) {
        y := RowTop()
        Label(y, text)
        OnOff(CX + CW - 78, y, SetPend[key] = "1", Flipper(key))
    }

    ; Not a setting you save — a thing that's happening right now, flipped
    ; the moment you click it.
    LiveSwitch(text, on, cb) {
        y := RowTop()
        Label(y, text)
        OnOff(CX + CW - 78, y, on, cb)
    }

    CardEdit(text, value, hint) {
        y := RowTop()
        g.SetFont("s10 c" t.text)
        g.Add("Text", "x" (CX + 16) " y" (y + 3) " w" (CW - 200) " h20"
            . " Background" t.panel, text)
        ed := g.Add("Edit", "x" (CX + CW - 94) " y" (y + 10) " w78 h26 Center"
                  . " -E0x200 Background" t.panelHot " c" t.text, value)
        Round(ed, 8)
        if (hint != "") {
            g.SetFont("s8 c" t.dim)
            g.Add("Text", "x" (CX + 16) " y" (y + RowH - 17) " w" (CW - 130) " h14"
                . " Background" t.panel, hint)
        }
        return ed
    }

    ; The pills are drawn after the label, so they'd quietly cover it — give
    ; the label only the room they don't want, and size them to what's left.
    CardSegment(text, key, options) {
        y := RowTop()
        Label(y, text, 118)
        each := (CW - 152 - (options.Length - 1) * 6) // options.Length
        span := options.Length * each + (options.Length - 1) * 6
        for i, opt in options
            Pill("x" (CX + CW - 16 - span + (i - 1) * (each + 6)) " y" (y + 8)
               . " w" each " h30 Center", opt, SetPend[key] = opt, Setter(key, opt))
    }

    KeyRow(text, key) {
        y := RowTop()
        Label(y, text)
        Pill("x" (CX + CW - 176) " y" (y + 8) " w160 h30 Center",
             Pretty(SetPend[key]), false, Rebinder(key, text))
    }

    ; One app in the list: the name, an Enter switch, and a ✕ to drop it.
    ; Selecting one opens its name for editing right underneath.
    AppRow(name, hint, pickAs, idx := 0, enter := "") {
        y := RowTop()
        picked := (SetPend["target"] = pickAs)
        n := g.Add("Text", "x" (CX + 8) " y" (y + 4) " w" (CW - (idx ? 118 : 16))
                 . " h" (RowH - 8) " +0x200 +0x80 Background"
                 . (picked ? t.accent : t.panel)
                 . " c" (picked ? t.accentText : t.text), "   " name)
        n.ToolTip := hint
        n.OnEvent("Click", Picker(pickAs))
        Round(n, 9)
        if !picked
            Hover(n, t.panel, t.panelHot)
        if !idx
            return
        on := (enter = "1")
        e := Pill("x+6 yp w62 h" (RowH - 8) " Center", on ? "Enter" : "no ↵",
                  false, Toggler(idx), !on)
        e.ToolTip := "Press Enter after pasting`nOn for a chat box, off for a document"
        x := Pill("x+6 yp w30 h" (RowH - 8) " Center", "✕", false, Dropper(idx), true)
        x.ToolTip := "Remove " name
    }

    ; One handler per row, so each keeps its own index — a closure made inside
    ; the loop would share the last one.
    Picker(what)       => (*) => SetOne("target", what)
    Toggler(i)         => (*) => ToggleEnter(i)
    Dropper(i)         => (*) => RemoveApp(i)
    Spotter(i)         => (*) => SetSpot(g, i)
    Setter(key, val)   => (*) => SetOne(key, val)
    Pager(name)        => (*) => TurnTo(name)
    Flipper(key)       => (*) => SetOne(key, SetPend[key] = "1" ? "0" : "1")
    Rebinder(key, lbl) => (*) => Rebind(key, lbl)

    PickByClick(*) {
        if (app := ClickApp(g))
            AddApp(app)
    }
    PickByBrowse(*) {
        if (app := ChooseApp())
            AddApp(app)
    }

    Save(*) {
        global SetCtl, SetPend, SetTheme, cfg, Filling
        CommitRename()                          ; a half-typed name still counts
        for key, c in SetCtl {                  ; and so does a half-typed box
            if (key != "rename")
                try SetPend[key] := Trim(c.Value)
        }
        if (SetPend["dictkey"] = "") {
            MsgBox("Which key does your dictation app use?", "AI Snap", "Iconx 4096")
            return
        }
        if (!IsInteger(SetPend["filltimeout"])
            || SetPend["filltimeout"] < 0 || SetPend["filltimeout"] > 86400) {
            MsgBox("The filling timeout has to be a whole number of seconds,"
                 . " from 0 (never) up to a day.", "AI Snap", "Iconx 4096")
            return
        }
        IniWrite(SetPend["target"],  cfg, "Target",    "Active")
        IniWrite(SetPend["theme"],   cfg, "Look",      "Theme")
        IniWrite(SetPend["dict"],    cfg, "Hotkeys",   "Dictate")
        IniWrite(SetPend["snip"],    cfg, "Hotkeys",   "SnipAndSend")
        IniWrite(SetPend["sel"],     cfg, "Hotkeys",   "CopySelection")
        IniWrite(SetPend["all"],     cfg, "Hotkeys",   "CopyAllOnPage")
        IniWrite(SetPend["post"],    cfg, "Hotkeys",   "Post")
        IniWrite(SetPend["fill"],    cfg, "Hotkeys",   "Fill")
        IniWrite(SetPend["dictkey"], cfg, "Dictation", "Key")
        IniWrite(SetPend["comp"],    cfg, "Behavior",  "Composer")
        IniWrite(SetPend["auto"],    cfg, "Behavior",  "AutoSend")
        IniWrite(SetPend["restore"], cfg, "Behavior",  "RestoreFocus")
        IniWrite(SetPend["advance"], cfg, "Fill",      "Advance")
        IniWrite(SetPend["filltimeout"], cfg, "Fill", "Timeout")
        ; Saving restarts the script, and a restart forgets everything that
        ; isn't in this file — including a mode you switched on ten seconds
        ; ago on this very page. Carry it over.
        IniWrite(Filling ? "1" : "0", cfg, "Fill", "Resume")
        SetTheme := ""                          ; keep the theme, don't undo it
        CloseSettings()
        Reload()                                ; restart with the new settings
    }
}

; ---- what the app list's buttons do -----------------------------------------
; New apps are written to config.ini straight away, so they survive Cancel.
AddApp(app) {
    global Apps, cfg, SetPend, SetFresh
    for a in Apps {
        if (a.name = app.name) {                ; already there — just select it
            SetOne("target", a.name)
            return
        }
    }
    Apps.Push(app)
    IniWrite(AppLine(app), cfg, "Apps", app.name)
    Log("added app " app.name " → " app.match)
    SetFresh := true                            ; so the cursor lands in its name
    SetOne("target", app.name)
}

; Anything pinned to an app has to let go of it when the app goes.
TargetAfterRemove(target, gone) => (target = gone) ? "Auto" : target

RemoveApp(i) {
    global Apps, cfg, SetPend, Active
    if (i > Apps.Length)
        return
    gone := Apps[i].name
    Apps.RemoveAt(i)
    IniDelete(cfg, "Apps", gone)
    Log("removed app " gone)
    ; Two things can be pinned to it: what's saved in config.ini, and what
    ; you've clicked but not saved. They aren't always the same one, and
    ; either left behind points config.ini at an app that isn't there.
    if (Active != (kept := TargetAfterRemove(Active, gone))) {
        Active := kept
        IniWrite(kept, cfg, "Target", "Active")
    }
    SetOne("target", TargetAfterRemove(SetPend["target"], gone))
}

ToggleEnter(i) {
    global Apps, cfg
    if (i > Apps.Length)
        return
    a := Apps[i]
    a.enter := (a.enter = "1") ? "0" : "1"
    IniWrite(AppLine(a), cfg, "Apps", a.name)
    RefreshSettings()
}

; Bring the app up so there's something to point at, then let you click the
; box you type in. Esc during the pick clears it back to no spot at all.
SetSpot(g, i) {
    global Apps, cfg, Active, LastApp
    if (i > Apps.Length)
        return
    a := Apps[i]
    ; Aim FocusTarget at this one, then put the real target back — including
    ; when it throws, because a window can close between being found and being
    ; asked about, and leaving Active pinned here would silently redirect
    ; every send from then on. A bare try swallows, so the next line always runs.
    was := Active, Active := a.name
    ok := false
    try ok := FocusTarget()
    Active := was
    if !ok {
        TrayTip("Can't find " a.name, "Open it first, then set where to type.", 2)
        RefreshSettings()
        return
    }
    a.spot := GrabSpot(g, a)
    IniWrite(AppLine(a), cfg, "Apps", a.name)
    Log("typing spot for " a.name " = " (a.spot = "" ? "cleared" : a.spot))
    RefreshSettings()
}

; ---- pick from what's already open ------------------------------------------
; The shortest route of the three: everything you have open, one click to add.
ShowRunningApps() {
    t := ThemeNow()
    found := RunningApps()
    p := Gui("-Caption +AlwaysOnTop +ToolWindow +Owner" (SetGui ? SetGui.Hwnd : ""),
             "Running apps")
    p.MarginX := 18, p.MarginY := 16
    ApplyTheme(p, t)
    p.SetFont("s12 w600 c" t.text)
    p.Add("Text", "xm ym w300", "What's open right now")
    p.SetFont("s8 c" t.dim)
    p.Add("Text", "xm y+4 w340", "Click one to send to it from now on.")
    p.SetFont("s10 c" t.text)

    if !found.Length
        p.Add("Text", "xm y+14 w340", "Nothing to show — open an app first.")
    for i, app in found {
        r := p.Add("Text", "xm y+8 w340 h38 +0x200 +0x80 Background" t.panel
                 . " c" t.text, "   " app.name)
        r.ToolTip := app.exe "`n" app.title
        r.OnEvent("Click", Take(app))
        Round(r, 10)
        Hover(r, t.panel, t.panelHot)
    }
    ThemeButton(p, t, "Cancel", "xm y+16 w340 h38", (*) => p.Destroy())
    p.OnEvent("Escape", (*) => p.Destroy())
    p.OnEvent("Close",  (*) => p.Destroy())
    p.Show()

    Take(app) => (*) => (p.Destroy(), AddApp(app))
}
