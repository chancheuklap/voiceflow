import Foundation

/// macOS 备忘录集成 — 通过 AppleScript 将文字追加到当天的日记笔记
/// 所有笔记存放在备忘录的 "VoiceFlow" 文件夹中
struct NotesIntegration {

    private static let folderName = "VoiceFlow"

    /// 启动时确保今天的日记笔记存在（h1 标题格式）
    static func ensureTodayNote() {
        let noteTitle = todayTitle()
        let noteBody = "<h1>\(escapeForHTML(noteTitle))</h1>"

        let script = """
        tell application "Notes"
            -- 确保 VoiceFlow 文件夹存在
            set folderName to "\(folderName)"
            set targetFolder to missing value
            repeat with f in folders of default account
                if name of f is folderName then
                    set targetFolder to f
                    exit repeat
                end if
            end repeat
            if targetFolder is missing value then
                set targetFolder to make new folder at default account with properties {name:folderName}
            end if

            -- 在该文件夹中查找今天的笔记
            set noteTitle to "\(escapeForAppleScript(noteTitle))"
            set matchingNotes to notes of targetFolder whose name is noteTitle
            if (count of matchingNotes) = 0 then
                make new note at targetFolder with properties {body:"\(escapeForAppleScript(noteBody))"}
            end if
        end tell
        """

        DispatchQueue.global(qos: .utility).async {
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
            if let error = error {
                print("Notes ensureToday error: \(error)")
            } else {
                print("Journal: today's note ready (\(noteTitle))")
            }
        }
    }

    /// 追加一条日记到备忘录
    static func appendToDaily(text: String) {
        let noteTitle = todayTitle()

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timestamp = timeFormatter.string(from: Date())

        let entryHTML = "<div><br></div><div>\(timestamp)  \(escapeForHTML(text))</div>"
        let newNoteBody = "<h1>\(escapeForHTML(noteTitle))</h1>\(entryHTML)"

        let script = """
        tell application "Notes"
            -- 确保 VoiceFlow 文件夹存在
            set folderName to "\(folderName)"
            set targetFolder to missing value
            repeat with f in folders of default account
                if name of f is folderName then
                    set targetFolder to f
                    exit repeat
                end if
            end repeat
            if targetFolder is missing value then
                set targetFolder to make new folder at default account with properties {name:folderName}
            end if

            -- 查找今天的笔记，追加或创建
            set noteTitle to "\(escapeForAppleScript(noteTitle))"
            set noteEntry to "\(escapeForAppleScript(entryHTML))"
            set matchingNotes to notes of targetFolder whose name is noteTitle
            if (count of matchingNotes) > 0 then
                set theNote to item 1 of matchingNotes
                set body of theNote to (body of theNote) & noteEntry
            else
                make new note at targetFolder with properties {body:"\(escapeForAppleScript(newNoteBody))"}
            end if
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
            if let error = error {
                print("Notes error: \(error)")
            } else {
                print("Journal saved: \(timestamp) \(text)")
            }
        }
    }

    private static func todayTitle() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return "VoiceFlow 日记 - \(dateFormatter.string(from: Date()))"
    }

    private static func escapeForAppleScript(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func escapeForHTML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
