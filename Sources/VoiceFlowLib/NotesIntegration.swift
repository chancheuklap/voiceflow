import Foundation

/// macOS 备忘录集成 — 通过 AppleScript 将文字追加到当天的日记笔记
struct NotesIntegration {

    /// 启动时确保今天的日记笔记存在（空笔记，只有标题）
    static func ensureTodayNote() {
        let noteTitle = todayTitle()

        let script = """
        tell application "Notes"
            set noteTitle to "\(escapeForAppleScript(noteTitle))"
            set matchingNotes to notes of default account whose name is noteTitle
            if (count of matchingNotes) = 0 then
                make new note at default account with properties {name:noteTitle, body:""}
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

    /// 追加一条日记到备忘录（当天的笔记不存在则自动创建）
    static func appendToDaily(text: String) {
        let noteTitle = todayTitle()

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timestamp = timeFormatter.string(from: Date())

        let entry = "\(timestamp)  \(text)"

        // AppleScript: 查找今天的笔记，存在则追加，不存在则创建
        let script = """
        tell application "Notes"
            set noteTitle to "\(escapeForAppleScript(noteTitle))"
            set noteEntry to "\(escapeForAppleScript(entry))"

            set matchingNotes to notes of default account whose name is noteTitle
            if (count of matchingNotes) > 0 then
                set theNote to item 1 of matchingNotes
                set body of theNote to (body of theNote) & "<br>" & noteEntry
            else
                make new note at default account with properties {name:noteTitle, body:noteEntry}
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
                print("Journal saved: \(entry)")
            }
        }
    }

    private static func todayTitle() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return "VoiceFlow 日记 - \(dateFormatter.string(from: Date()))"
    }

    /// 转义 AppleScript 字符串中的特殊字符
    private static func escapeForAppleScript(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
