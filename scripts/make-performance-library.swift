// Creates synthetic Markdown files in a NEW directory. Never targets a real library.
// Usage: swift scripts/make-performance-library.swift /private/tmp/new-library 5000
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let count = Int(arguments[2]), [5, 5000].contains(count) else {
    fatalError("Usage: make-performance-library.swift NEW_DIRECTORY 5|5000")
}
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let manager = FileManager.default
guard !manager.fileExists(atPath: root.path) else {
    fatalError("Refusing to overwrite an existing directory")
}
try manager.createDirectory(at: root, withIntermediateDirectories: true)
// Stay below the app's default 200-child-directory discovery limit.
let folderCount = count == 5 ? 2 : 100
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = TimeZone(secondsFromGMT: 0)
formatter.dateFormat = "yyyy-MM-dd"
let epoch = Date(timeIntervalSince1970: 1_789_257_600)
for index in 0..<count {
    let folder = index % folderCount
    let directory = root.appendingPathComponent("Folder-\(folder / 10)/Topic-\(folder)")
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = index % 10 == 0
        ? formatter.string(from: epoch.addingTimeInterval(-Double(index / 10) * 86_400))
        : String(format: "Research-%05d", index)
    let body = "# Audit note \(index)\n\n#work/topic\(index % 20) #research #batch\(index % 5)\n\n"
        + String(repeating: "A synthetic paragraph for measuring library loading, previews, and search. ", count: 14)
        + "\n- [ ] Review finding \(index)\n"
    let file = directory.appendingPathComponent(name).appendingPathExtension("md")
    try body.write(to: file, atomically: true, encoding: .utf8)
    try manager.setAttributes([.modificationDate: epoch.addingTimeInterval(-Double(index % 400) * 86_400)], ofItemAtPath: file.path)
}
print("Created \(count) synthetic Markdown files at \(root.path)")
