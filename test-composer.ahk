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

ExitApp(fails)
