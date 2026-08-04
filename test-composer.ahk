#Requires AutoHotkey v2.0
; Smoke test for the composer queue. Run it: it exits 0 when everything passed,
; or with the number of failures (and writes test-composer.log).
#Include ai-snap.ahk

global fails := 0
Check(ok, what) {
    global fails
    if !ok {
        fails++
        FileAppend("FAIL: " what "`n", A_ScriptDir "\test-composer.log")
    }
}

try FileDelete(A_ScriptDir "\test-composer.log")

Check(Preview("  a`n b   c  ") = "a b c",              "Preview squashes whitespace")
Check(StrLen(Preview(StrReplace(Format("{:46}", ""), " ", "x"))) = 46, "Preview truncates to 45 + …")

A_Clipboard := "hello world"
ClipWait(2)
Attach("Text: " Preview(A_Clipboard), 0, 120)
Check(CompItems.Length = 1,                            "one attachment queued")
Check(Comp != 0,                                       "composer window opened")
Check(CompItems[1].label = "Text: hello world",        "label is the preview")

A_Clipboard := "second grab"
ClipWait(2)
Attach("Text: " Preview(A_Clipboard), 0, 120)
Check(CompItems.Length = 2,                            "second attachment stacks up")

; the saved grab must survive the clipboard changing under it
A_Clipboard := "clobbered"
A_Clipboard := CompItems[1].data
ClipWait(2)
Check(A_Clipboard = "hello world",                     "saved grab round-trips")

RemoveAttachment(1)
Check(CompItems.Length = 1,                            "remove drops one")
Check(CompItems[1].label = "Text: second grab",        "remove drops the right one")

; Store puts the box away without losing a thing, and the next grab brings it
; all back — that's the whole point of the button.
CompEdit.Value := "half-written note"
StoreComposer()
Check(Comp = 0,                                        "store closes the window")
Check(CompItems.Length = 1,                            "store keeps the attachments")
Check(CompNote = "half-written note",                  "store keeps the note")
ShowComposer(0)
Check(Comp != 0,                                       "next grab reopens it")
Check(CompEdit.Value = "half-written note",            "the note comes back")

; each chip's ✕ must drop its own item, not whatever was selected last
Attach("Third", 0, 120)
Check(CompItems.Length = 2,                            "attach while open stacks up")
Remover(1)()                                           ; the first chip's ✕
Check(CompItems.Length = 1 && CompItems[1].label = "Third", "the right chip goes")

for name in ThemeNames {
    Theme := name
    Check(ThemeNow().accent != "" && ThemeNow().font != "", "theme " name " is complete")
}
Theme := "something deleted from config.ini"
Check(ThemeNow().accent = Themes()["Claude Code"].accent, "unknown theme falls back")

CloseComposer()
Check(Comp = 0 && CompItems.Length = 0 && CompNote = "", "close clears everything")

; --- sending to any app, not just AI chats ---------------------------------
; A chat needs Enter to fire the message; Word would just get a blank line.
tmp := A_ScriptDir "\test-apps.ini"
try FileDelete(tmp)
FileAppend("[Apps]`n"
         . "Chatty = ahk_exe chat.exe | chat.exe | 1`n"
         . "Wordy = Word | C:\word.lnk | 0`n"
         . "Olde = ahk_exe old.exe`n", tmp)
real := cfg, cfg := tmp
picked := LoadApps()
cfg := real
try FileDelete(tmp)
Check(picked.Length = 3,                               "three apps parsed")
Check(picked[2].match = "Word" && picked[2].launch = "C:\word.lnk", "title match + .lnk launch")
Check(picked[2].enter = "0",                           "document app keeps enter=0")
Check(picked[3].enter = "1",                           "an old two-field line still sends Enter")

LastApp := picked[1]
Check(EnterOK(),                                       "chat app presses Enter")
LastApp := picked[2]
Check(!EnterOK(),                                      "document app does not press Enter")
LastApp := 0
Check(EnterOK(),                                       "unknown target still presses Enter")

; --- naming an app you clicked on ------------------------------------------
Check(NameFromWindow("Book1 - Excel", "EXCEL.EXE") = "Excel",   "name comes off the title")
Check(NameFromWindow("a - b - Visual Studio Code", "Code.exe") = "Visual Studio Code",
                                                                "the last dash wins")
Check(NameFromWindow("Claude", "Claude.exe") = "Claude",        "no dash falls back to the exe")
Check(NameFromWindow("", "WINWORD.EXE") = "WINWORD",            "no title at all still names it")
; browsers are backwards — the last bit is the browser, not the app you want
Check(NameFromWindow("T3 Chat - Google Chrome", "chrome.exe") = "T3 Chat",
                                                                "a tab is named after the page")
Check(NameFromWindow("Google Flow - Aug 04, 05:42 PM - Opera", "opera.exe")
        = "Google Flow - Aug 04, 05:42 PM",                     "the WHOLE page title, not its tail")
Check(NameFromWindow("T3 Chat", "chrome.exe") = "T3 Chat",      "a web app with no dash keeps its name")
Check(NameFromWindow("", "chrome.exe") = "chrome",              "a nameless browser window still names it")
Check(MatchFor("Excel", "EXCEL.EXE") = "ahk_exe EXCEL.EXE",     "an app matches on its exe")
Check(MatchFor("T3 Chat", "chrome.exe") = "T3 Chat ahk_exe chrome.exe",
                                                                "a browser tab matches the title too")

; the picker must offer the app you're looking at, and never the shell
open := RunningApps()
Check(open.Length > 0,                                          "running apps are found at all")
shell := false
for a in open
    if (a.exe = "explorer.exe")
        shell := true
Check(!shell,                                    "the taskbar and desktop are never offered")
seen := Map(), dupe := false
for a in open
    dupe := dupe || seen.Has(a.exe), seen[a.exe] := true
Check(!dupe,                                     "one entry per program, not per window")

; "!1" has to read as something a human would recognise
Check(Pretty("!1") = "Alt + 1",                                 "a hotkey reads as words")
Check(Pretty("^+#f4") = "Ctrl + Shift + Win + F4",              "modifiers come out in order")

; removing an app has to unpin BOTH the saved target and the one you clicked,
; or config.ini is left pointing at something that isn't there any more
Check(TargetAfterRemove("Claude", "Claude") = "Auto",           "the pinned app falls back to Auto")
Check(TargetAfterRemove("Claude", "ChatGPT") = "Claude",        "removing another app leaves it alone")
Check(TargetAfterRemove("Auto", "Claude") = "Auto",             "Auto stays Auto")
; (no space before the ; in that string — AHK reads " ;" as a comment even
;  inside quotes, and eats the rest of the line)
Check(CleanName(";Notes[1] = x|y ") = "-Notes-1- - x-y",        "config.ini's own syntax is stripped out")

; pinned to an app that can't be launched must not start a different one
Active := "Olde", Apps := picked        ; "Olde" is the line with no launch part
Check(AppToLaunch() = 0,                               "a pinned app with no launch starts nothing")
Active := "Auto"
Check(AppToLaunch().name = "Chatty",                   "Auto still starts the first one that can")
Apps := LoadApps()

; --- waiting for you to click an app ---------------------------------------
; Opens Notepad, minimises it, then "clicks" it a moment later. We must pick up
; that exact window, ignoring the taskbar and our own windows on the way.
; (No "grabs nothing when idle" check — Windows moves focus around on its own
; when a script activates a window, so that one can't be tested honestly here.)
Run("notepad.exe")
if WinWait("ahk_class Notepad", , 10) {
    np := WinExist("ahk_class Notepad")
    WinMinimize("ahk_id " np)
    Sleep(400)
    ClickIt() {
        WinRestore("ahk_id " np)
        WinActivate("ahk_id " np)
    }
    SetTimer(ClickIt, -800)
    Check(GrabNextWindow(WinActive("A")) = np,          "picks up the window you switch to")
    Check(NameFromWindow(WinGetTitle("ahk_id " np), "Notepad.exe") = "Notepad",
                                                        "and names it sensibly")

    try WinClose("ahk_id " np)
} else {
    Check(false, "could not open Notepad to test with")
}

; The one that actually bit: hiding the settings box hands focus straight back
; to the app you were about to click, so nothing ever "changes" and we waited
; forever. A click has to count on its own, even on the window already in front.
;
; The flag is set directly rather than by a fake click — a scripted click can't
; be relied on to take the foreground, so it lands on whatever really is on top
; and the test measures Windows' focus rules instead of ours.
Clicked() {
    global ClickSeen
    ClickSeen := true
}
if (here := WinActive("A")) {
    SetTimer(Clicked, -300)
    Check(GrabNextWindow(here) = here,     "a click counts on the window you're already in")
}

ExitApp(fails)
