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
global Active       := IniRead(cfg, "Target",   "Active",         "Auto")
global RestoreFocus := IniRead(cfg, "Behavior", "RestoreFocus",   "1")
global AutoSend     := IniRead(cfg, "Behavior", "AutoSend",       "1")
global Composer     := IniRead(cfg, "Behavior", "Composer",       "1")
global AttachWait   := IniRead(cfg, "Behavior", "AttachWait",     "400")
global Debug        := IniRead(cfg, "Behavior", "Debug",          "0")

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
A_IconTip := "AI Snap  —  sending to: " Active

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

; Focus the AI app, press Enter, then hand focus back. (The manual send key.)
Post(prev) {
    KeyWait("Alt", "T1")
    if !FocusTarget()
        return
    Send("{Enter}")
    Sleep(80)
    GoBack(prev)
}

; Press Enter — but only when auto-send is switched on.
Submit() {
    global AutoSend
    if (AutoSend = "1") {
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
    id := FindTarget()
    if !id {                                   ; nothing open — try launching one
        if !(app := AppToLaunch()) {
            TrayTip("No AI app found",
                    "Open one, or add it under [Apps] in config.ini.", 3)
            return 0
        }
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
; supported app you used most recently (window Z-order = most recent first).
FindTarget() {
    global Apps, Active
    if (Active != "Auto") {
        for a in Apps {
            if (a.name = Active) {
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
                owned[hwnd] := true
        for hwnd in WinGetList()                ; every window, most recent first
            if owned.Has(hwnd)
                return hwnd
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

; Read the [Apps] section into a list of {name, match, launch}.
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
        if (match != "")
            apps.Push({ name:   name,
                        match:  match,
                        launch: Trim(bits.Has(2) ? bits[2] : "") })
    }
    return apps
}

; Write a line to ai-snap.log when Debug=1 in config.ini.
Log(msg) {
    global Debug
    if (Debug = "1")
        try FileAppend(FormatTime(, "HH:mm:ss") "  " msg "`n", A_ScriptDir "\ai-snap.log")
}

; ============================================================================
;  the composer — a little box that holds everything you've grabbed so you can
;  type a note before it goes. Snips, highlighted text, whole pages: they all
;  stack up in here, in order, and go across in one message when you hit Send.
;
;  It's a plain AutoHotkey window, so it works no matter which program you
;  grabbed from — nothing is added to the app you're in.
; ============================================================================
global Comp      := 0     ; the composer window while it's open, 0 when it isn't
global CompItems := []    ; what's attached so far: [{label, data, wait}]
global CompPrev  := 0     ; the window to hand focus back to when we're done
global CompEdit  := 0, CompList := 0

; Take whatever is on the clipboard right now, park it in the composer, and
; bring the box up. ClipboardAll() keeps the *whole* clipboard — an image stays
; an image — so pasting it later is identical to pasting it now.
Attach(label, prev, wait) {
    global CompItems
    CompItems.Push({ label: label, data: ClipboardAll(), wait: wait })
    Log("attached: " label)
    ShowComposer(prev)
}

; Open the box, or just bring it back to the front if it's already open.
ShowComposer(prev) {
    global Comp, CompItems, CompPrev, CompEdit, CompList
    if Comp {
        Comp.Show()
        RefreshAttachments()
        return
    }
    CompPrev := prev
    Comp := g := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox", "Send to AI")
    g.SetFont("s10", "Segoe UI")

    g.Add("Text", "xm", "Going to your AI:")
    CompList := g.Add("ListBox", "xm y+4 w380 r4")
    g.Add("Button", "xm y+4 w130", "Remove selected").OnEvent("Click", RemoveAttachment)
    g.Add("Text", "x+10 yp+5 w240 cGray", "Grab more any time — it all stacks up.")

    g.Add("Text", "xm y+12", "Add a note (Enter sends  ·  Shift+Enter = new line):")
    CompEdit := g.Add("Edit", "xm y+4 w380 r5 +Multi +WantReturn")

    g.Add("Button", "xm y+12 w130", "Send").OnEvent("Click", ComposerSend)
    g.Add("Button", "x+10 w90", "Cancel").OnEvent("Click", CancelComposer)
    g.OnEvent("Escape", CancelComposer)
    g.OnEvent("Close",  CancelComposer)

    RefreshAttachments()
    g.Show()
    CompEdit.Focus()                  ; land in the note box, ready to type
}

; Redraw the list of what's attached.
RefreshAttachments() {
    global CompItems, CompList
    CompList.Delete()
    for i, it in CompItems
        CompList.Add([i ". " it.label])
}

; Drop something you didn't mean to grab.
RemoveAttachment(*) {
    global CompItems, CompList, CompEdit
    if (i := CompList.Value)
        CompItems.RemoveAt(i)
    RefreshAttachments()
    CompEdit.Focus()
}

; Send the lot: each attachment in the order you grabbed it, then your note,
; then Enter. Restoring each saved clipboard and pasting is what lets one
; message carry an image, some copied text and your own typing together.
ComposerSend(*) {
    global Comp, CompItems, CompPrev, CompEdit
    if !Comp
        return
    note  := CompEdit.Value
    items := CompItems
    prev  := CompPrev
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
    Send("{Enter}")                   ; you clicked Send, so we always send
    Sleep(80)
    GoBack(prev)
}

CancelComposer(*) {
    global CompPrev
    prev := CompPrev
    Log("composer cancelled")
    CloseComposer()
    GoBack(prev)
}

CloseComposer() {
    global Comp, CompItems, CompPrev
    if Comp
        Comp.Destroy()
    Comp := 0, CompItems := [], CompPrev := 0
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
    global cfg, Apps, Active
    g := Gui("+AlwaysOnTop -MinimizeBox", "AI Snap settings")
    g.SetFont("s10", "Segoe UI")

    g.Add("Text", "xm", "Send to:")
    names := ["Auto — whichever app I used last"]
    for a in Apps
        names.Push(a.name)
    ddTarget := g.Add("DropDownList", "x+6 yp-4 w240", names)
    ddTarget.Choose(1)
    for i, a in Apps
        if (a.name = Active)
            ddTarget.Choose(i + 1)

    g.Add("Text", "xm y+16", "Click a box, then press the keys you'd like to use:")

    g.Add("Text",   "xm y+14 w190",       "Talk to my AI (dictation)")
    hkDict := g.Add("Hotkey", "x+6 yp-4 w150", IniRead(cfg, "Hotkeys", "Dictate",       "!1"))
    g.Add("Text",   "xm y+10 w190",       "Snip screenshot → AI")
    hkSnip := g.Add("Hotkey", "x+6 yp-4 w150", IniRead(cfg, "Hotkeys", "SnipAndSend",   "!2"))
    g.Add("Text",   "xm y+10 w190",       "Copy highlighted → AI")
    hkSel  := g.Add("Hotkey", "x+6 yp-4 w150", IniRead(cfg, "Hotkeys", "CopySelection", "!3"))
    g.Add("Text",   "xm y+10 w190",       "Select-all page → AI")
    hkAll  := g.Add("Hotkey", "x+6 yp-4 w150", IniRead(cfg, "Hotkeys", "CopyAllOnPage", "!4"))
    g.Add("Text",   "xm y+10 w190",       "Send manually")
    hkPost := g.Add("Hotkey", "x+6 yp-4 w150", IniRead(cfg, "Hotkeys", "Post",          "!0"))

    g.Add("Text", "xm y+14 w190", "My dictation push-to-talk key")
    edDictKey := g.Add("Edit", "x+6 yp-4 w60", IniRead(cfg, "Dictation", "Key", "F4"))
    g.Add("Text", "x+10 yp+4", "(as set in Handy)")

    cbComp := g.Add("Checkbox", "xm y+16", "Open the composer so I can add a note first")
    cbComp.Value := (IniRead(cfg, "Behavior", "Composer", "1") = "1")
    cbAuto := g.Add("Checkbox", "xm y+8", "Send to the AI automatically every time")
    cbAuto.Value := (IniRead(cfg, "Behavior", "AutoSend", "1") = "1")
    cbRestore := g.Add("Checkbox", "xm y+8", "Return to my window after each action")
    cbRestore.Value := (IniRead(cfg, "Behavior", "RestoreFocus", "1") = "1")

    g.Add("Button", "xm y+18 w120 Default", "Save && Reload").OnEvent("Click", Save)
    g.Add("Button", "x+10 w90", "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show()

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
