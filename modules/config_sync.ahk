; ============================================================
; Module: Config Sync — import from D:\AI-HUB-SYNC on startup,
;         export on close + every 30 minutes
; ============================================================

global SYNC_DIR := DirExist("D:\") ? "D:\AI-HUB-SYNC" : "C:\AI-HUB-SYNC"

; Files to sync between local config and sync directory
global SYNC_FILES := ["hotkeys.ini", "hotstrings.sav", "settings.ini", "prompts.json",
                      "storage.json", "sysprompts.json", "research_links.json"]

; Import: if sync copy is newer than local, overwrite local
Sync_Import() {
    global CFG_DIR, SYNC_DIR, SYNC_FILES
    if !DirExist(SYNC_DIR)
        return  ; nothing to import from

    for , f in SYNC_FILES {
        syncFile  := SYNC_DIR "\" f
        localFile := CFG_DIR "\" f
        if !FileExist(syncFile)
            continue
        ; If local doesn't exist, always import
        if !FileExist(localFile) {
            try FileCopy(syncFile, localFile, true)
            continue
        }
        ; Compare timestamps — import if sync is newer
        syncTime  := FileGetTime(syncFile, "M")
        localTime := FileGetTime(localFile, "M")
        if (syncTime > localTime)
            try FileCopy(syncFile, localFile, true)
    }
}

; Export: copy all local config files to sync directory
Sync_Export() {
    global CFG_DIR, SYNC_DIR, SYNC_FILES
    if !DirExist(SYNC_DIR)
        DirCreate(SYNC_DIR)

    for , f in SYNC_FILES {
        localFile := CFG_DIR "\" f
        if FileExist(localFile)
            try FileCopy(localFile, SYNC_DIR "\" f, true)
    }
}
