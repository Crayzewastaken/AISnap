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
SetTitleMatchMode(2)              ; allow partial window-title matches
InstallKeybdHook()                ; see keys even when another app swallows them

; --- settings (read from config.ini, with safe fallbacks) -------------------
global Apps         := LoadApps()
global LastApp      := 0          ; the app we last sent to — see EnterOK()
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

keyDict := IniRead(cfg, "Hotkeys", "Dictate",        "!1")
keySnip := IniRead(cfg, "Hotkeys", "SnipAndSend",    "!2")
keySel  := IniRead(cfg, "Hotkeys", "CopySelection",  "!3")
keyAll  := IniRead(cfg, "Hotkeys", "CopyAllOnPage",  "!4")
keyPost := IniRead(cfg, "Hotkeys", "Post",           "!0")

; --- bind the hotkeys -------------------------------------------------------
Hotkey(keyDict, DictateToAI)
Hotkey(keySnip, SnipAndSend)
Hotkey(keySel,  CopySelectionToAI)
Hotkey(keyAll,  CopyAllToAI)
Hotkey(keyPost, PostToAI)

; The little bot, instead of AutoHotkey's H. Missing icon isn't worth dying over.
try TraySetIcon(A_ScriptDir "\ai-snap.ico")
OnMessage(0x201, DragCard)                  ; 0x201 = left mouse button down

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
A_TrayMenu.Add()
A_TrayMenu.Add("Get Handy (voice dictation)…", (*) => InstallHandy())
A_TrayMenu.Add("Edit config.ini directly", (*) => Run(cfg))
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
UpdateTrayTip()

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
    A_Clipboard := ""                 ; clear so we can detect the new snip
    Send("#+s")                       ; Windows built-in "snip region to clipboard"
    if !ClipWait(60, 1) {             ; wait up to 60s for the snip (1 = images too)
        if Comp
            ShowComposer(prev)        ; snip cancelled — put the box back
        return
    }
    if (Composer = "1") {
        Attach("Screenshot", prev, AttachWait)
        return
    }
    PasteIntoAI(prev, AttachWait)
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
;  shared helpers
; ============================================================================

; Copy from the window you're in (using copyKeys), then paste into the AI app.
GrabTextToAI(copyKeys, label) {
    global Comp, CompPrev, Composer
    prev := Comp ? CompPrev : WinActive("A")
    KeyWait("Alt", "T1")              ; release Alt or ^c becomes ^!c and fails
    A_Clipboard := ""                 ; clear so we know when the copy lands
    Send(copyKeys)                    ; the copy happens in YOUR window
    if !ClipWait(2) {                 ; wait up to 2s for text
        TrayTip("Nothing copied", "No text was selected to send.", 2)
        return
    }
    if (Composer = "1") {
        Attach(label ": " Preview(A_Clipboard), prev, 120)
        return
    }
    PasteIntoAI(prev, 120)
}

; Focus the AI app, paste the clipboard, send it, then hand focus back.
PasteIntoAI(prev, settle) {
    if !FocusTarget()
        return
    Send("^v")
    Sleep(settle)                     ; let it attach before we send
    Submit()
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
    global LastApp
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
    Log("FocusTarget id=" id " activated=" (ok ? "yes" : "no"))
    return ok
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
                if (id := WinExist(a.match))
                    return id
                DetectHiddenWindows(true)       ; also catch tray-hidden windows
                return WinExist(a.match)
            }
        }
    }
    ; Auto — visible windows first (real Z-order), then hidden ones.
    for hidden in [false, true] {
        DetectHiddenWindows(hidden)
        owned := Map()
        for a in Apps
            for hwnd in WinGetList(a.match)
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
Launch(app) {
    target := (InStr(app.launch, "\") || InStr(app.launch, ".exe"))
        ? app.launch
        : "explorer.exe shell:AppsFolder\" app.launch
    try Run(target)
}

; Read the [Apps] section into a list of {name, match, launch, enter}.
; Third field is optional: 0 = don't press Enter after pasting (documents).
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
                        enter:  (ent = "" ? "1" : ent) })
    }
    return apps
}

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
    return { name: name, match: match, launch: path, enter: "1" }
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
    Log("click-pick: got " id " — " WinGetTitle("ahk_id " id))
    return AppFromWindow(id)
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

IsBrowser(exe) => exe ~= "i)^(chrome|msedge|firefox|brave|opera|vivaldi)\.exe$"

; Anything that would break a config.ini line, or turn it into a comment.
CleanName(s) => RegExReplace(Trim(s), "[=|;\[\]]", "-")

; What to call the app you clicked. Windows apps title their windows
; "Book1 - Excel", so the bit after the last dash is the app itself.
; Browsers are backwards: there the last bit is the browser and the bit before
; it is the page you actually want — "T3 Chat - Google Chrome" → "T3 Chat".
NameFromWindow(title, exe) {
    title := Trim(title)
    bits  := StrSplit(title, " - ")
    pick  := ""
    if IsBrowser(exe) {
        ; Everything up to the browser's own name is the page. Don't take just
        ; the last piece of it — "Google Flow - Aug 04, 05:42 PM - Opera" would
        ; come back called "Aug 04, 05:42 PM".
        pick := (bits.Length > 1)
            ? Trim(SubStr(title, 1, InStr(title, " - ", , -1) - 1))
            : title                         ; a web app titled just "T3 Chat"
    } else if (bits.Length > 1)             ; an empty title splits into nothing,
        pick := Trim(bits[bits.Length])     ; so never reach into bits blind
    return pick != "" ? pick : RegExReplace(exe, "i)\.exe$", "")
}

; Browsers need the title in the match as well: every tab and web app shares
; one exe, so "ahk_exe chrome.exe" alone would find whichever tab was last open.
MatchFor(name, exe) => IsBrowser(exe) ? name " ahk_exe " exe : "ahk_exe " exe

; Everything we can work out about a window on our own. Enter defaults to on
; because most things you send to are a chat box — flip it on the row if not.
AppFacts(id, exe := "") {
    if (exe = "")
        exe := WinGetProcessName("ahk_id " id)
    path := ""
    try path := WinGetProcessPath("ahk_id " id)     ; so we can reopen it later
    name := CleanName(NameFromWindow(WinGetTitle("ahk_id " id), exe))
    return { name: name, match: MatchFor(name, exe), launch: path, enter: "1",
             exe: exe, title: WinGetTitle("ahk_id " id) }
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
ApplyTheme(g, t) {
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
    HoverAt := under
    for b in live {
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
    CompItems.Push({ label: label, data: ClipboardAll(), wait: wait })
    Log("attached: " label)
    UpdateTrayTip()
    if Comp
        RebuildComposer()             ; already open — redraw it with the new chip
    else
        ShowComposer(prev)
}

; There's no title bar to grab, so dragging the heading moves the card.
; 0xA1 = "act like the mouse went down on the caption", 2 = the caption.
DragCard(wParam, lParam, msg, hwnd) {
    global Comp, CompHead, SetGui, SetHead
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
    if !FocusTarget()
        return
    for it in items {
        A_Clipboard := it.data        ; put that exact grab back on the clipboard
        Sleep(60)
        Send("^v")
        Sleep(it.wait)                ; images especially need a moment to attach
    }
    if (Trim(note) != "") {
        A_Clipboard := note
        ClipWait(2)
        Send("^v")
        Sleep(120)
    }
    if EnterOK() {                    ; you clicked Send, so we always send —
        Send("{Enter}")               ; unless it's Word and Enter means nothing
        Sleep(80)
    }
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
    SetPend["dictkey"] := IniRead(cfg, "Dictation", "Key",           "F4")
    SetPend["comp"]    := IniRead(cfg, "Behavior",  "Composer",      "1")
    SetPend["auto"]    := IniRead(cfg, "Behavior",  "AutoSend",      "1")
    SetPend["restore"] := IniRead(cfg, "Behavior",  "RestoreFocus",  "1")
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
        IniWrite(a.match " | " a.launch " | " a.enter, cfg, "Apps", want)
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
    global cfg, Apps, Theme, ThemeNames
    global SetGui, SetHead, SetCtl, SetPend, SetTheme, SetFresh
    SettingsState()
    if SetGui {
        try SetGui.Destroy()
        SetGui := 0
    }
    SetCtl := Map()
    if (SetTheme = "")                        ; remember the saved one first,
        SetTheme := Theme                     ; Cancel has to be able to undo this
    Theme := SetPend["theme"]                 ; so the card repaints as you pick
    t := ThemeNow()
    W := 412                                  ; content width everything lines up to
    RowH := 34                                ; and one row height, everywhere
    SetGui := g := Gui("-Caption +AlwaysOnTop +ToolWindow", "AI Snap settings")
    g.MarginX := 20, g.MarginY := 18
    ApplyTheme(g, t)

    ; ---- heading -----------------------------------------------------------
    g.SetFont("s12 w600 c" t.text)
    SetHead := g.Add("Text", "xm ym w" (W - 40) " +0x100", "AI Snap")   ; 0x100 = clickable
    g.SetFont("s12 c" t.dim)
    g.Add("Text", "x+0 yp-2 w32 h28 Center +0x200 +0x100 Background" t.bg, "✕")
        .OnEvent("Click", (*) => CloseSettings())

    ; ---- your apps ---------------------------------------------------------
    Section("Send to")
    Row("Auto", "whichever app I used last", "Auto")
    for i, a in Apps
        Row(a.name, a.match, a.name, i, a.enter)

    g.SetFont("s10 c" t.text)
    ThemeButton(g, t, "Running apps",  "xm y+12 w132 h" RowH, (*) => ShowRunningApps())
    ThemeButton(g, t, "Click an app",  "x+8 w132 h" RowH,     PickByClick)
    ThemeButton(g, t, "Browse…",       "x+8 w132 h" RowH,     PickByBrowse)

    ; ---- keys --------------------------------------------------------------
    Section("Keys")
    KeyRow("Talk to my AI (dictation)",  "dict")
    KeyRow("Snip screenshot → send",     "snip")
    KeyRow("Send what I've highlighted", "sel")
    KeyRow("Select all → send",          "all")
    KeyRow("Send manually",              "post")

    g.SetFont("s10 c" t.text)
    g.Add("Text", "xm y+6 w" (W - 190) " h" RowH " +0x200", "My push-to-talk key")
    SetCtl["dictkey"] := ed := g.Add("Edit",
        "x+8 yp+3 w72 h28 Center -E0x200 Background" t.panel " c" t.text, SetPend["dictkey"])
    g.SetFont("s8 c" t.dim)
    g.Add("Text", "x+8 yp+6 w96", "as set in Handy")

    ; ---- look --------------------------------------------------------------
    Section("Look")
    Segment("theme", ThemeNames)

    ; ---- options -----------------------------------------------------------
    Section("Options")
    Toggle("comp",    "Ask me for a note first")
    Toggle("auto",    "Send automatically")
    Toggle("restore", "Come back to my window")

    ; ---- save --------------------------------------------------------------
    ThemeButton(g, t, "Save and reload", "xm y+18 w" (W - 140) " h40", Save, true)
    ThemeButton(g, t, "Cancel", "x+8 w132 h40", (*) => CloseSettings())
    g.OnEvent("Escape", (*) => CloseSettings())
    g.OnEvent("Close",  (*) => CloseSettings())

    Round(ed, 8)
    g.Show()
    ; Just added one? Land in its name box with the text selected, so a page
    ; title that came out too long can be typed over straight away.
    if (SetFresh && SetCtl.Has("rename")) {
        SetCtl["rename"].Focus()
        PostMessage(0xB1, 0, -1, SetCtl["rename"])       ; EM_SETSEL = select all
    }
    SetFresh := false

    ; A quiet all-caps label with breathing room above it. Cheaper than a rule
    ; line and it does the same job — it tells your eye a new group started.
    Section(label) {
        g.SetFont("s8 w600 c" t.dim)
        g.Add("Text", "xm y+18 w" W, StrUpper(label))
        g.SetFont("s10 c" t.text)
    }

    ; A pill: flat, rounded, accent when it's the one that's on.
    Pill(opts, label, on, cb, quiet := false) {
        p := g.Add("Text", opts " +0x200 +0x80 Background" (on ? t.accent : t.panel)
                 . " c" (on ? t.accentText : (quiet ? t.dim : t.text)), label)
        p.OnEvent("Click", cb)
        Round(p, 10)
        if !on
            Hover(p, t.panel, t.panelHot)
        return p
    }

    ; One app in the list: the name, an Enter toggle, and a ✕ to drop it.
    ; The name's tooltip is the window it looks for, so the list stays clean
    ; but you can still see what an entry actually targets.
    Row(name, hint, pickAs, idx := 0, enter := "") {
        picked := (SetPend["target"] = pickAs)
        n := Pill("xm y+6 w" (idx ? W - 112 : W) " h" RowH, "   " name, picked,
                  Picker(pickAs))
        n.ToolTip := hint
        if !idx
            return
        on := (enter = "1")
        e := Pill("x+8 yp w64 h" RowH " Center", on ? "Enter" : "no ↵", false,
                  Toggler(idx), !on)
        e.ToolTip := "Press Enter after pasting`nOn for a chat box, off for a document"
        x := Pill("x+8 yp w32 h" RowH " Center", "✕", false, Dropper(idx), true)
        x.ToolTip := "Remove " name
        if !picked
            return
        ; The one you've selected gets its name in a box, so a long or wrong
        ; one can be fixed here instead of in a dialog you have to go and find.
        SetCtl["rename"] := ed := g.Add("Edit",
            "xm y+6 w" W " h28 -E0x200 Background" t.panel " c" t.text, name)
        Round(ed, 8)
        g.SetFont("s8 c" t.dim)
        g.Add("Text", "xm y+4 w" W, RegExMatch(hint, "i)^ahk_exe\s")
            ? "Call it whatever you like."
            : "Keep this to a short bit of its title bar — it's how the window"
            . " is found, so a whole page title stops matching tomorrow.")
        g.SetFont("s10 c" t.text)
    }

    KeyRow(label, key) {
        g.SetFont("s10 c" t.text)
        g.Add("Text", "xm y+6 w" (W - 168) " h" RowH " +0x200", label)
        Pill("x+8 yp w160 h" RowH " Center", Pretty(SetPend[key]), false,
             Rebinder(key, label))
    }

    ; Three side-by-side pills — one is on, and picking is one click, not two.
    ; NB: don't call that width "w". AHK variable names are case-insensitive, so
    ; a nested function's "w" IS the enclosing "W", and every control after this
    ; one silently gets the wrong width.
    Segment(key, options) {
        each := (W - (options.Length - 1) * 8) // options.Length
        for i, opt in options
            Pill((i = 1 ? "xm y+8" : "x+8 yp") " w" each " h" RowH " Center", opt,
                 SetPend[key] = opt, Setter(key, opt))
    }

    Toggle(key, label) {
        on := (SetPend[key] = "1")
        Pill("xm y+6 w" (W - 76) " h" RowH, "   " label, false, Flipper(key))
        Pill("x+8 yp w68 h" RowH " Center", on ? "on" : "off", on, Flipper(key), true)
    }

    ; One handler per row, so each keeps its own index — a closure made inside
    ; the loop would share the last one.
    Picker(what)       => (*) => SetOne("target", what)
    Toggler(i)         => (*) => ToggleEnter(i)
    Dropper(i)         => (*) => RemoveApp(i)
    Setter(key, val)   => (*) => SetOne(key, val)
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
        global SetCtl, SetPend, SetTheme, cfg
        CommitRename()                          ; a half-typed name still counts
        SetPend["dictkey"] := Trim(SetCtl["dictkey"].Value)
        if (SetPend["dictkey"] = "") {
            MsgBox("Which key does your dictation app use?", "AI Snap", "Iconx 4096")
            return
        }
        IniWrite(SetPend["target"],  cfg, "Target",    "Active")
        IniWrite(SetPend["theme"],   cfg, "Look",      "Theme")
        IniWrite(SetPend["dict"],    cfg, "Hotkeys",   "Dictate")
        IniWrite(SetPend["snip"],    cfg, "Hotkeys",   "SnipAndSend")
        IniWrite(SetPend["sel"],     cfg, "Hotkeys",   "CopySelection")
        IniWrite(SetPend["all"],     cfg, "Hotkeys",   "CopyAllOnPage")
        IniWrite(SetPend["post"],    cfg, "Hotkeys",   "Post")
        IniWrite(SetPend["dictkey"], cfg, "Dictation", "Key")
        IniWrite(SetPend["comp"],    cfg, "Behavior",  "Composer")
        IniWrite(SetPend["auto"],    cfg, "Behavior",  "AutoSend")
        IniWrite(SetPend["restore"], cfg, "Behavior",  "RestoreFocus")
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
    IniWrite(app.match " | " app.launch " | " app.enter, cfg, "Apps", app.name)
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
    IniWrite(a.match " | " a.launch " | " a.enter, cfg, "Apps", a.name)
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
