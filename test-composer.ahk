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

CompList.Choose(1)
RemoveAttachment()
Check(CompItems.Length = 1,                            "remove drops one")
Check(CompItems[1].label = "Text: second grab",        "remove drops the right one")

CloseComposer()
Check(Comp = 0 && CompItems.Length = 0,                "close clears everything")

ExitApp(fails)
