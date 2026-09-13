// Validates Storage's production batch insertion against the previous
// sequential duplicate behavior. Run from any directory with:
//   swift scripts/test-batch-insertion.swift

import Foundation

let fileManager = FileManager.default
let invocationDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let scriptURL = URL(fileURLWithPath: #filePath, relativeTo: invocationDirectory).standardizedFileURL
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let storageSourceURL = projectRoot
    .appendingPathComponent("FSNotesCore")
    .appendingPathComponent("Business")
    .appendingPathComponent("Storage.swift")
let storageSource = try String(contentsOf: storageSourceURL, encoding: .utf8)

guard let implementationStart = storageSource.range(of: "    private struct NoteIdentity"),
      let implementationEnd = storageSource.range(of: "    public func contains(note: Note)",
                                                   range: implementationStart.upperBound..<storageSource.endIndex)
else {
    fatalError("Could not locate the production batch insertion implementation")
}

let productionImplementation = String(storageSource[implementationStart.lowerBound..<implementationEnd.lowerBound])
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("fsnotes-batch-insertion-\(UUID().uuidString)", isDirectory: true)
try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporaryDirectory) }

let runnerURL = temporaryDirectory.appendingPathComponent("runner.swift")
let executableURL = temporaryDirectory.appendingPathComponent("runner")
let moduleCacheURL = temporaryDirectory.appendingPathComponent("module-cache", isDirectory: true)
try fileManager.createDirectory(at: moduleCacheURL, withIntermediateDirectories: true)
let runner = """
import Foundation

final class Project: NSObject {
    var url: URL

    init(url: URL) {
        self.url = url
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Project else { return false }
        return url == other.url
    }

    override var hash: Int { url.hashValue }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.url == rhs.url
    }
}

final class Note: NSObject {
    var id: String
    var name: String
    var project: Project
    var url: URL

    init(id: String, name: String, project: Project) {
        self.id = id
        self.name = name
        self.project = project
        self.url = project.url.appendingPathComponent(name)
    }
}

final class HarnessStorage {
    private let noteListLock = NSRecursiveLock()
    private var _noteList: [Note]

    init(notes: [Note]) {
        _noteList = notes
    }

    \(productionImplementation)

    func snapshot() -> [Note] {
        noteListLock.lock()
        defer { noteListLock.unlock() }
        return _noteList
    }
}

func sequentialResult(existing: [Note], incoming: [Note]) -> [Note] {
    var result = existing
    for note in incoming {
        if !result.contains(where: { $0.name == note.name && $0.project == note.project }) {
            result.append(note)
        }
    }
    return result
}

func ids(_ notes: [Note]) -> [String] {
    notes.map { $0.id }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let root = URL(fileURLWithPath: "/tmp/fsnotes-batch-insertion-test")
let projectURL = root.appendingPathComponent("A")
let projectA = Project(url: projectURL)
let projectAClone = Project(url: projectURL)
let projectB = Project(url: root.appendingPathComponent("B"))

let existing = [
    Note(id: "existing-alpha", name: "Alpha.md", project: projectA),
    Note(id: "existing-other-folder", name: "Alpha.md", project: projectB)
]
let incoming = [
    Note(id: "duplicate-existing", name: "Alpha.md", project: projectAClone),
    Note(id: "accepted-beta", name: "Beta.md", project: projectA),
    Note(id: "accepted-case", name: "alpha.md", project: projectA),
    Note(id: "accepted-other-folder", name: "Alpha.md", project: projectB),
    Note(id: "accepted-gamma", name: "Gamma.md", project: projectA),
    Note(id: "duplicate-batch", name: "Gamma.md", project: projectAClone),
    Note(id: "accepted-different-project", name: "Alpha.md", project: Project(url: root.appendingPathComponent("C")))
]

let expected = sequentialResult(existing: existing, incoming: incoming)
let storage = HarnessStorage(notes: existing)
storage.add(incoming)
expect(ids(storage.snapshot()) == ids(expected), "Batch result differs from sequential result")

let emptyStorage = HarnessStorage(notes: existing)
emptyStorage.add([])
expect(ids(emptyStorage.snapshot()) == ids(existing), "Empty batch changed storage")

let singleStorage = HarnessStorage(notes: existing)
singleStorage.add(incoming[0])
expect(ids(singleStorage.snapshot()) == ids(sequentialResult(existing: existing, incoming: [incoming[0]])),
       "Single-note insertion changed behavior")

print("Batch insertion regression checks passed (\\(expected.count) retained notes, order and duplicate semantics match).")
"""
try runner.write(to: runnerURL, atomically: true, encoding: String.Encoding.utf8)

let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
compiler.arguments = [runnerURL.path, "-module-cache-path", moduleCacheURL.path, "-o", executableURL.path]
let compilerOutput = Pipe()
compiler.standardOutput = compilerOutput
compiler.standardError = compilerOutput
try compiler.run()
compiler.waitUntilExit()
let compileLog = String(data: compilerOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
guard compiler.terminationStatus == 0 else {
    print(compileLog)
    exit(1)
}

let test = Process()
test.executableURL = executableURL
let testOutput = Pipe()
test.standardOutput = testOutput
test.standardError = testOutput
try test.run()
test.waitUntilExit()
let testLog = String(data: testOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
print(testLog, terminator: "")
exit(test.terminationStatus)
