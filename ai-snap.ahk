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

; In Auto mode, if nothing is open, launch the first app that knows how.
AppToLaunch() {
    global Apps, Active
    for a in Apps
        if (a.name = Active && a.launch != "")
            return a
    for a in Apps
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
    name := RegExReplace(SubStr(path, InStr(path, "\", , -1) + 1), "\.(lnk|exe)$", "")
    name := RegExReplace(name, "[=|]", "-")     ; those two would break config.ini
    target := path
    if (SubStr(path, -4) = ".lnk")
        try FileGetShortcut(path, &target)      ; shortcuts point at the real exe
    ; Match on the exe where we can. Store apps have no exe behind the shortcut,
    ; so fall back to matching the app's name inside the window title —
    ; "Word" finds "Report.docx - Word" because partial titles already match.
    match := (target != "" && SubStr(target, -4) = ".exe")
        ? "ahk_exe " SubStr(target, InStr(target, "\", , -1) + 1)
        : name
    yes := MsgBox("Press Enter after pasting into " name "?`n`n"
                . "Yes — it's a chat box, Enter sends the message.`n"
                . "No — it's a document, Enter would just add a blank line.",
                  "AI Snap", "YesNo Iconi") = "Yes"
    return { name: name, match: match, launch: path, enter: yes ? "1" : "0" }
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
    global Comp, CompHead
    if (Comp && CompHead && hwnd = CompHead.Hwnd)
        PostMessage(0xA1, 2, 0, , "ahk_id " Comp.Hwnd)
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
;  settings window — click a box, press the keys you want, Save.
; ============================================================================
ShowSettings(*) {
    global cfg, Apps, Active, Theme, ThemeNames
    t := ThemeNow()
    g := Gui("+AlwaysOnTop -MinimizeBox", "AI Snap settings")
    ApplyTheme(g, t)

    g.Add("Text", "xm", "Send to:")
    names := ["Auto — whichever app I used last"]
    for a in Apps
        names.Push(a.name)
    names.Push("Choose an app…")            ; always the last row — see PickApp
    ddTarget := g.Add("DropDownList", "x+6 yp-4 w240 -E0x200 Background" t.panel " c" t.text, names)
    ddTarget.Choose(1)
    for i, a in Apps
        if (a.name = Active)
            ddTarget.Choose(i + 1)
    pickRow  := names.Length                ; where "Choose an app…" sits
    prevPick := ddTarget.Value              ; what to go back to if you cancel
    ddTarget.OnEvent("Change", PickApp)

    g.Add("Text", "xm y+10", "Look:")
    ddTheme := g.Add("DropDownList", "x+6 yp-4 w240 -E0x200 Background" t.panel " c" t.text,
                     ThemeNames)
    ddTheme.Choose(1)
    for i, n in ThemeNames
        if (n = Theme)
            ddTheme.Choose(i)

    g.Add("Text", "xm y+16", "Click a box, then press the keys you'd like to use:")

    g.Add("Text",   "xm y+14 w190",       "Talk to my AI (dictation)")
    hkDict := g.Add("Hotkey", "x+6 yp-4 w150 h26", IniRead(cfg, "Hotkeys", "Dictate",       "!1"))
    g.Add("Text",   "xm y+10 w190",       "Snip screenshot → AI")
    hkSnip := g.Add("Hotkey", "x+6 yp-4 w150 h26", IniRead(cfg, "Hotkeys", "SnipAndSend",   "!2"))
    g.Add("Text",   "xm y+10 w190",       "Copy highlighted → AI")
    hkSel  := g.Add("Hotkey", "x+6 yp-4 w150 h26", IniRead(cfg, "Hotkeys", "CopySelection", "!3"))
    g.Add("Text",   "xm y+10 w190",       "Select-all page → AI")
    hkAll  := g.Add("Hotkey", "x+6 yp-4 w150 h26", IniRead(cfg, "Hotkeys", "CopyAllOnPage", "!4"))
    g.Add("Text",   "xm y+10 w190",       "Send manually")
    hkPost := g.Add("Hotkey", "x+6 yp-4 w150 h26", IniRead(cfg, "Hotkeys", "Post",          "!0"))

    g.Add("Text", "xm y+14 w190", "My dictation push-to-talk key")
    edDictKey := g.Add("Edit", "x+6 yp-4 w60 h26 -E0x200 Background" t.panel " c" t.text,
                       IniRead(cfg, "Dictation", "Key", "F4"))
    g.SetFont("s9 c" t.dim)
    g.Add("Text", "x+10 yp+4", "(as set in Handy)")
    g.SetFont("s10 c" t.text)

    cbComp := g.Add("Checkbox", "xm y+16", "Open the composer so I can add a note first")
    cbComp.Value := (IniRead(cfg, "Behavior", "Composer", "1") = "1")
    cbAuto := g.Add("Checkbox", "xm y+8", "Send to the AI automatically every time")
    cbAuto.Value := (IniRead(cfg, "Behavior", "AutoSend", "1") = "1")
    cbRestore := g.Add("Checkbox", "xm y+8", "Return to my window after each action")
    cbRestore.Value := (IniRead(cfg, "Behavior", "RestoreFocus", "1") = "1")

    ThemeButton(g, t, "Save and reload", "xm y+18 w160 h38", Save, true)
    ThemeButton(g, t, "Cancel", "x+10 w120 h38", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())

    for c in [ddTarget, ddTheme, hkDict, hkSnip, hkSel, hkAll, hkPost, edDictKey]
        Round(c, 6)
    g.Show()

    ; "Choose an app…" opens the Windows picker, then slots the app you chose
    ; into the list above itself and selects it. Saved to config.ini straight
    ; away, so it's there next time even if you hit Cancel on this window.
    PickApp(*) {
        if (ddTarget.Value != pickRow) {
            prevPick := ddTarget.Value
            return
        }
        ddTarget.Choose(prevPick)               ; never leave "Choose an app…" showing
        if !(app := ChooseApp())
            return
        Apps.Push(app)
        IniWrite(app.match " | " app.launch " | " app.enter, cfg, "Apps", app.name)
        ddTarget.Delete(pickRow)                ; re-add it under the new name
        ddTarget.Add([app.name, "Choose an app…"])
        prevPick := pickRow
        pickRow  += 1
        ddTarget.Choose(prevPick)
    }

    Save(*) {
        for hk in [hkDict, hkSnip, hkSel, hkAll, hkPost] {
            if (hk.Value = "") {
                MsgBox("Every box needs a key combo.", "AI Snap", "Iconx 4096")
                return
            }
        }
        if (Trim(edDictKey.Value) = "") {
            MsgBox("Which key does your dictation app use?", "AI Snap", "Iconx 4096")
            return
        }
        pick := ddTarget.Value                  ; 1 = Auto, else Apps[pick-1]
        IniWrite(pick = 1 ? "Auto" : Apps[pick - 1].name, cfg, "Target", "Active")
        IniWrite(ThemeNames[ddTheme.Value], cfg, "Look", "Theme")
        IniWrite(hkDict.Value, cfg, "Hotkeys", "Dictate")
        IniWrite(hkSnip.Value, cfg, "Hotkeys", "SnipAndSend")
        IniWrite(hkSel.Value,  cfg, "Hotkeys", "CopySelection")
        IniWrite(hkAll.Value,  cfg, "Hotkeys", "CopyAllOnPage")
        IniWrite(hkPost.Value, cfg, "Hotkeys", "Post")
        IniWrite(Trim(edDictKey.Value), cfg, "Dictation", "Key")
        IniWrite(cbComp.Value    ? "1" : "0", cfg, "Behavior", "Composer")
        IniWrite(cbAuto.Value    ? "1" : "0", cfg, "Behavior", "AutoSend")
        IniWrite(cbRestore.Value ? "1" : "0", cfg, "Behavior", "RestoreFocus")
        g.Destroy()
        Reload()                                ; restart with the new settings
    }
}
