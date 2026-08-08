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
         . "Chatty = ahk_exe chat.exe | chat.exe | 1 | 0.5000,0.9200`n"
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
Check(picked[1].spot = "0.5000,0.9200",                "a typing spot round-trips")
Check(picked[2].spot = "" && picked[3].spot = "",      "and is empty when it was never set")
Check(AppLine(picked[1]) = "ahk_exe chat.exe | chat.exe | 1 | 0.5000,0.9200",
                                                       "the line is written back the same way")
Check(AppLine(picked[3]) = "ahk_exe old.exe |  | 1",   "no spot means no fourth field")

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
; a browser is named after the browser and found by it, so it opens on
; whatever tab you're actually on rather than one frozen page title
Check(NameFromWindow("T3 Chat - Google Chrome", "chrome.exe") = "Google Chrome",
                                                                "a browser is named after itself")
Check(NameFromWindow("Google Flow - Aug 04, 05:42 PM - Opera", "opera.exe") = "Opera",
                                                                "however busy the page title is")
Check(NameFromWindow("", "chrome.exe") = "chrome",              "a nameless browser window still names it")
Check(MatchFor("Excel", "EXCEL.EXE") = "ahk_exe EXCEL.EXE",     "an app matches on its exe")
Check(MatchFor("anything at all", "opera.exe") = "ahk_exe opera.exe",
                                                                "and so does a browser, whatever it's called")

; the picker must offer the app you're looking at, and never the shell
open := RunningApps()
Check(open.Length > 0,                                          "running apps are found at all")
; explorer.exe IS allowed when it's a real folder window, so name the two
; windows that must never be offered rather than banning the whole program.
me := DllCall("GetCurrentProcessId")
DetectHiddenWindows(false)
if (desk := WinExist("ahk_class Progman"))
    Check(!IsAppWindow(desk, me),                "the desktop is never offered")
if (bar := WinExist("ahk_class Shell_TrayWnd"))
    Check(!IsAppWindow(bar, me),                 "and neither is the taskbar")
seen := Map(), dupe := false
for a in open
    dupe := dupe || seen.Has(a.exe), seen[a.exe] := true
Check(!dupe,                                     "one entry per program, not per window")

; fill mode must not react to AI Snap's own clipboard work — a snip meant for
; your AI would otherwise be force-pasted into whatever you're filling too
Check(ClipMine = 0,                                             "nothing is holding the clipboard at rest")
ClipHold()
Check(ClipMine = 1,                                             "a hold registers")
ClipHold(), ClipRelease()
Check(ClipMine = 1,                                             "holds nest, so the inner one can't free it")
ClipRelease()
Check(ClipMine = 0,                                             "and the outer one does")
ClipRelease()
Check(ClipMine = 0,                                             "an extra release can't go negative")
Check(SafeInt("120", 9) = 120 && SafeInt("", 9) = 9 && SafeInt("later", 9) = 9,
                                                                "a hand-edited timeout can't blow up a timer")

; what you copied must never reach the log file, only what KIND it was
Check(Redact("Text: my bank password") = "Text",                "the log gets the kind, not the text")
Check(Redact("Whole page: Dear Mr Smith, your account") = "Whole page",
                                                                "and not a whole page either")
Check(Redact("Screenshot") = "Screenshot",                      "something with no preview is left alone")

; a typing spot is a fraction of the window, so it can never point outside it
Check(InWindow("0.5") = 0.5,                                    "a normal spot is left alone")
Check(InWindow("5") = 1 && InWindow("-3") = 0,                  "a hand-edited spot is pulled back inside")
Check(InWindow("nonsense") = 0.5,                               "and nonsense lands in the middle")

; a double-click has to be quick AND on the spot — one fast click, or two
; clicks either side of the button, are not a double
Check(IsDoubleClick(80, 0, 0),                                  "quick and in the same place is a double")
Check(!IsDoubleClick(80, 300, 0),                               "quick but miles away is not")
Check(!IsDoubleClick(DoubleTime() + 500, 0, 0),                 "same place but slow is not")
Check(IsDoubleClick(DoubleTime(), DoubleSlop(36), DoubleSlop(37)),
                                                                "right on Windows' own limits still counts")

; a saved button position can't strand it off the edge of a screen you unplugged
Check(OnScreen("300", 48, 1920) = 300,                          "a sane position is kept")
Check(OnScreen("99999", 48, 1920) = 1872,                       "past the right edge is pulled back")
Check(OnScreen("-500", 48, 1920) = 0,                           "and so is past the left")
Check(OnScreen("", 48, 1920) = 0,                               "a blank position starts at the corner")

; a paste only ever goes into the window we lined up
LastTarget := 0
Check(Paste() = true,                                           "with no target, a paste just happens")
LastTarget := -1                                                ; a window that isn't the active one
Check(Paste() = false,                                          "if something else took focus, it doesn't")
LastTarget := 0

; "!1" has to read as something a human would recognise
Check(Pretty("!1") = "Alt + 1",                                 "a hotkey reads as words")
Check(Pretty("^+#f4") = "Ctrl + Shift + Win + F4",              "modifiers come out in order")

; removing an app has to unpin BOTH the saved target and the one you clicked,
; or config.ini is left pointing at something that isn't there any more
Check(TargetAfterRemove("Claude", "Claude") = "Auto",           "the pinned app falls back to Auto")
Check(TargetAfterRemove("Claude", "ChatGPT") = "Claude",        "removing another app leaves it alone")
Check(TargetAfterRemove("Auto", "Claude") = "Auto",             "Auto stays Auto")

; renaming in place — and an old entry pinned to one tab's title gets healed
Check(RematchFor("Opera", "Web Gecko - Google Search ahk_exe opera.exe")
        = "ahk_exe opera.exe",                 "renaming drops a stale title match")
Check(RematchFor("Chat", "ahk_exe Claude.exe") = "ahk_exe Claude.exe",
                                               "renaming an ordinary app leaves the match")
Check(RematchFor("Word 365", "Word") = "Word 365",
                                               "an app matched by title alone follows the name")
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
; These two watch the real desktop, so another app stealing focus fails them
; without anything being wrong. One retry: a genuine break fails both times.
Twice(fn, what) {
    Check(fn() || fn(), what)
}

global np := 0
Run("notepad.exe")
if WinWait("ahk_class Notepad", , 10) {
    np := WinExist("ahk_class Notepad")
    ClickIt() {
        global np
        WinRestore("ahk_id " np)
        WinActivate("ahk_id " np)
    }
    SwitchTest() {
        global np
        WinMinimize("ahk_id " np)
        Sleep(400)
        SetTimer(ClickIt, -800)
        return GrabNextWindow(WinActive("A")) = np
    }
    Twice(SwitchTest,                                   "picks up the window you switch to")
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
ClickTest() {
    if !(here := WinActive("A"))
        return false
    SetTimer(Clicked, -300)
    return GrabNextWindow(here) = here
}
Twice(ClickTest,                           "a click counts on the window you're already in")

ExitApp(fails)
