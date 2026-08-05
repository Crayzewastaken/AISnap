#Requires AutoHotkey v2.0
; Opens a settings window so it can be looked at, then quits. Not part of the
; app — it lives here so A_ScriptDir points at the real config.ini.
;   preview-ui.ahk            the settings card
;   preview-ui.ahk running    the "what's open right now" picker
;   preview-ui.ahk combo      the key-capture card
#Include ai-snap.ahk

lg := A_ScriptDir "\preview-ui.log"
try FileDelete(lg)
which := A_Args.Length ? A_Args[1] : "settings"
try {
    if (which = "running") {
        ShowRunningApps()
        win := p := 0
        for hwnd in WinGetList("ahk_class AutoHotkeyGUI")
            if (WinGetTitle("ahk_id " hwnd) = "Running apps")
                win := hwnd
    } else if (which = "combo") {
        SetTimer(() => FileAppend("combo card is up`n", lg), -1200)
        CaptureCombo("Snip screenshot → send")
        FileAppend("captured`n", lg)
        ExitApp(0)
    } else if (which = "welcome") {
        ShowWelcome()
        win := 0
        for hwnd in WinGetList("ahk_class AutoHotkeyGUI")
            if (WinGetTitle("ahk_id " hwnd) = "AI Snap welcome")
                win := hwnd
    } else {
        if (which != "settings")
            SetPage := which          ; "Keys", "Filling", "Options"
        ShowSettings()
        win := SetGui.Hwnd
    }
    WinGetPos(&x, &y, &w, &h, "ahk_id " win)
    FileAppend("ok " w "x" h " at " x "," y "`n", lg)
} catch as e
    FileAppend("ERROR: " e.Message " (line " e.Line ")`n", lg)
Sleep(90000)
ExitApp(0)
