#Requires AutoHotkey v2.1-
#Include <Aris/Chunjee/adash>

class TranscribeAnything {
    __New(HF_TOKEN?) {
        this.serverCap := 4
        this.queueCap := 6
        this.portStart := 8765
        this.load := Map()
        this.activeServers := Map()
        loop this.serverCap {
            port := this.portStart + (A_Index - 1)
            this.activeServers[port] := Map()
            this.activeServers[port].launched := 0
            this.load[port] := 0
        }
        this.runMode := "Hide"
        if IsSet(HF_TOKEN?)
            this.HF_TOKEN := HF_TOKEN
    }
    setHfToken(HF_TOKEN) {
        this.HF_TOKEN := HF_TOKEN
    }
    StartServer(port) {
        bat := this._findBatfromAris()
        Run('"' bat '" ' port, , , &batpid)
        this.WaitForConsoleText(batpid, "Uvicorn running on")
        this.activeServers[port].launched := 1
    }
    _findBatfromAris() { ;dynamically finds the dll from a versioned Aris installation
        if DirExist(A_ScriptDir "\lib\Aris\Qriist") ;"top level" install
            packageDir := A_ScriptDir "\lib\Aris\Qriist"
        else if DirExist(A_ScriptDir "\..\lib\Aris\Qriist") ;script one level down
            packageDir := A_ScriptDir "\..\lib\Aris\Qriist"
        else
            return ""
        loop files (packageDir "\TranscribeAnything@*"), "D" {
            TAdir := packageDir "\" A_LoopFileName
        }
        return TAdir "\lib\TA server start.bat"
    }

    WaitForConsoleText(pid, searchText, timeoutMs := 30000, intervalMs := 500) {
        start := A_TickCount
        loop {
            text := this.GetConsoleText(pid)
            if text && InStr(text, searchText)
                return true

            if(A_TickCount - start) >= timeoutMs
                return false

            Sleep intervalMs
        }
    }

    GetConsoleText(pid, charCount := 20000) {
        static STD_OUTPUT_HANDLE := -11
            , INVALID_HANDLE_VALUE := -1

        if !pid
            return ""

        if !DllCall("AttachConsole", "UInt", pid)
            return ""

        hConsole := DllCall("GetStdHandle", "UInt", STD_OUTPUT_HANDLE, "Ptr")
        if(hConsole = INVALID_HANDLE_VALUE) {
            DllCall("FreeConsole")
            return ""
        }

        buf := Buffer(charCount * 2, 0)
        if !DllCall("ReadConsoleOutputCharacterW"
            , "Ptr", hConsole
            , "Ptr", buf
            , "UInt", charCount
            , "UInt", 0
            , "UInt*", &charsRead := 0) {
            DllCall("FreeConsole")
            return ""
        }

        DllCall("FreeConsole")
        return StrGet(buf, charsRead, "UTF-16")
    }
    sendTA(input, output_dir) {
        port := this.findport()
        cmd := adash.join([
            "transcribe-anything",
            "--remote http://127.0.0.1:" port,
            '"' input '"',
            "--device whisperx",
            "--hf_token " this.HF_TOKEN,
            "--output_dir " '"' output_dir '"',
            "--model large-v3"
        ], " ")
        ; msgbox A_Clipboard := cmd
        proc := Run(cmd, , this.runMode)
        this.activeServers[port][proc] := A_NowUTC
        this.load[port] += 1
    }
    findport() {
        this.cullports()
        rotation := 999 ;start high

        for k, v in this.load {
            if v < rotation {
                rotation := v
                port := k
            }
        }
        if !this.activeServers[port].launched
            this.StartServer(port)
        return port
    }
    cullports() {
        culled := 0
        loop {
            for k, v in this.activeServers {
                port := k
                procObj := v
                toCull := []
                for k, v in procObj {
                    if !PID := ProcessExist(k)
                        toCull.Push(k)
                }
                for k, v in toCull {
                    PID := v
                    procObj.Delete(PID)
                    culled += 1
                    this.load[port] -= 1
                }
            }
            ;removed at least one process
            if culled
                return

            ;count total tracked load
            sum := 0
            for k, v in this.load
                sum += v

            ;at least 1 free spot
            if sum < (this.serverCap * this.queueCap)
                return
        }
    }
}
