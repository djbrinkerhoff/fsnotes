#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir}/../.."
home_source="${project_root}/FSNotes iOS/Helpers/HomeLibraryModel.swift"
daily_source="${project_root}/FSNotes iOS/View/DailyNotesView.swift"
overview_source="${project_root}/FSNotes/View/OverviewView.swift"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/fsnotes-performance.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
module_cache_dir="${work_dir}/module-cache"
mkdir -p "$module_cache_dir"

awk '/^@MainActor/{capture=1} capture {print}' "$home_source" > "$work_dir/home-model.swift"
awk '/^@MainActor/{capture=1} /^struct DailyNotesView/{exit} capture {print}' "$daily_source" > "$work_dir/daily-model.swift"
{
    echo '@available(macOS 12, *)'
    awk '/^final class OverviewModel/{capture=1} /^struct OverviewView/{exit} capture {print}' "$overview_source"
} > "$work_dir/overview-model.swift"
{
    echo '@available(macOS 12, *)'
    awk '/^private enum OverviewDateBucket/{capture=1} capture && /^private let overviewRelativeDateFormatter/{exit} capture && /^@available/{next} capture {print}' "$overview_source"
} > "$work_dir/overview-grouping.swift"

cat > "$work_dir/runner.swift" <<'SWIFT'
import Foundation
import Observation
import Combine

// Minimal stand-ins keep the benchmark independent of UIKit, Core Data and the
// app's file system. The production model source is injected below unchanged.
final class UIColor {}

struct FolderColor: Hashable {
    var platformColor: UIColor { UIColor() }
}

final class ProjectSettings {
    var folderIcon: String?
    var folderColor: FolderColor?
    var showInSidebar = true
}

final class Storage {
    static let instance = Storage()
    static func shared() -> Storage { instance }

    var noteList = [Note]()
    var projects = [Project]()
    var defaultProject: Project?

    func getDefault() -> Project? { defaultProject }
    func getAvailableProjects() -> [Project] {
        projects.filter { !$0.isDefault && !$0.isTrash && $0.settings.showInSidebar }
    }
    func getPinned() -> [Note]? { noteList.filter(\.isPinned) }
    func sortNotes(noteList: [Note]) -> [Note] {
        noteList.sorted { $0.modifiedLocalAt > $1.modifiedLocalAt }
    }
    func saveProjectsExpandState() {}
}

final class Project: NSObject {
    var url: URL
    var label: String
    var parent: Project?
    var isDefault: Bool
    var isTrash = false
    var isEncrypted = false
    var isExpanded = false
    var settings = ProjectSettings()

    init(url: URL, label: String, parent: Project? = nil, isDefault: Bool = false) {
        self.url = url
        self.label = label
        self.parent = parent
        self.isDefault = isDefault
    }

    func isLocked() -> Bool { false }
    func getFullLabel() -> String { label }
    func saveSettings() {}
}

final class Note: NSObject {
    var project: Project
    var url: URL
    var fileName: String
    var name: String
    var title = ""
    var preview = ""
    var tags = [String]()
    var isPinned = false
    var modifiedLocalAt: Date

    init(index: Int, project: Project, modifiedLocalAt: Date, fileName: String) {
        self.project = project
        self.url = project.url.appendingPathComponent("note-\(index).md")
        self.fileName = fileName
        self.name = fileName
        self.modifiedLocalAt = modifiedLocalAt
        super.init()
    }

    func isTrash() -> Bool { project.isTrash }
    func getTitle() -> String? { title.isEmpty ? nil : title }
    func getShortTitle() -> String { fileName }
    func getDateForLabel() -> String { "benchmark" }
}

enum NoteListDisplayMode {
    case list
    case cards
}

struct OverviewFolderItem: Identifiable {
    let id: String
    let title: String
    let noteCount: Int
    let project: Project
}

enum SidebarItemType: Int {
    case Home = 0
    case All = 1
    case Inbox = 2
    case Todo = 3
    case Untagged = 4
    case Trash = 5
    case Separator = 6
    var systemImage: String? { "folder" }
}

final class SidebarItem {
    var name: String
    var type: SidebarItemType
    init(name: String, type: SidebarItemType) {
        self.name = name
        self.type = type
    }
}

final class Sidebar {
    var items = [[SidebarItem]]()
    func reloadProjects() {}
}

final class SidebarTableView {
    var sidebar = Sidebar()
    func reloadProjects() {}
    func reloadData() {}
}

final class AppController {
    var sidebarTableView: SidebarTableView?
    var isLoadedDB = true
}

final class UIApplication {
    static let controller = AppController()
    static func getVC() -> AppController { controller }
}

enum UserDefaultsManagement {
    static var inlineTags = true
    static var expandedSidebarTags = [String]()
}

enum FolderIcon {
    static let defaultName = "folder"
}

enum LibraryNotifier {
    static func libraryDidChange() {}
}

extension Notification.Name {
    static let fsnotesLibraryDidChange = Notification.Name("benchmark.libraryDidChange")
}

// Production implementations are injected by run-performance.sh.
SWIFT

cat "$work_dir/home-model.swift" >> "$work_dir/runner.swift"
cat "$work_dir/daily-model.swift" >> "$work_dir/runner.swift"

cat >> "$work_dir/runner.swift" <<'SWIFT'

@available(macOS 12, *)
struct OverviewNoteItem: Identifiable {
    let id: String
    let title: String
    let preview: String
    let dateLabel: String
    let isPinned: Bool
    let note: Note
}

SWIFT
cat "$work_dir/overview-model.swift" >> "$work_dir/runner.swift"
cat "$work_dir/overview-grouping.swift" >> "$work_dir/runner.swift"

cat >> "$work_dir/runner.swift" <<'SWIFT'

struct BenchmarkStats: Codable {
    var medianMilliseconds: Double
    var p95Milliseconds: Double
    var samplesMilliseconds: [Double]
    var checksum: Int
}

struct Correctness: Codable {
    var expectedNotes: Int
    var expectedNonTrashNotes: Int
    var expectedTrashNotes: Int
    var expectedProjects: Int
    var expectedDailyDateKeys: Int
    var homeFolders: Int
    var homeStarred: Int
    var homeTrashCount: Int
    var dailyDateKeys: Int
    var dailyPreviousCount: Int
    var folderLookupProjects: Int
    var groupedItems: Int
    var cachedGroupedItems: Int
}

struct BenchmarkResult: Codable {
    var noteCount: Int
    var folderCount: Int
    var metrics: [String: BenchmarkStats]
    var correctness: Correctness
}

struct BenchmarkDocument: Codable {
    var generatedAt: String
    var toolchain: String
    var warmups: Int
    var samples: Int
    var clock: String
    var results: [BenchmarkResult]
}

struct BenchmarkDataset {
    var notes: [Note]
    var projects: [Project]
    var defaultProject: Project
    var dailyDateKeys: Int
    var dailyPreviousCount: Int
    var expectedSubtreeCounts: [URL: Int]
}

@available(macOS 12, *)
@MainActor
enum BenchmarkRunner {
    static let calendar = Calendar.current
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func durationMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    static func measure(_ action: () -> Int) -> BenchmarkStats {
        for _ in 0..<3 { _ = action() }
        var samples = [Double]()
        samples.reserveCapacity(15)
        var checksum = 0
        for _ in 0..<15 {
            let start = ContinuousClock.now
            checksum = action()
            let end = ContinuousClock.now
            samples.append(durationMilliseconds(start.duration(to: end)))
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let p95Index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return BenchmarkStats(
            medianMilliseconds: median,
            p95Milliseconds: sorted[p95Index],
            samplesMilliseconds: samples,
            checksum: checksum
        )
    }

    static func makeDataset(noteCount: Int, folderCount: Int) -> BenchmarkDataset {
        let rootURL = URL(fileURLWithPath: "/tmp/fsnotes-performance-\(noteCount)-\(folderCount)")
        let storage = Storage.shared()
        let defaultProject = Project(url: rootURL, label: "Default", isDefault: true)
        var projects = [defaultProject]
        var parent = defaultProject
        if folderCount > 0 {
            for index in 0..<folderCount {
                let project = Project(
                    url: rootURL.appendingPathComponent("folder-\(index)"),
                    label: String(format: "Folder %04d", index),
                    parent: parent
                )
                project.isExpanded = true
                projects.append(project)
                parent = project
            }
        }

        var notes = [Note]()
        notes.reserveCapacity(noteCount)
        var dailyDates = Set<Date>()
        let now = Date()
        for index in 0..<noteCount {
            let projectIndex = folderCount == 0 ? 0 : (index % folderCount) + 1
            let project = projects[projectIndex]
            let modified = now.addingTimeInterval(-Double(index) * 3_600)
            let isDaily = index % 10 == 0
            let fileName: String
            if isDaily {
                let day = calendar.startOfDay(for: now.addingTimeInterval(-Double(index / 10) * 86_400))
                fileName = dateFormatter.string(from: day)
                dailyDates.insert(day)
            } else {
                fileName = "note-\(index)"
            }
            let note = Note(index: index, project: project, modifiedLocalAt: modified, fileName: fileName)
            note.title = "Benchmark note \(index)"
            note.preview = String(repeating: "Performance fixture text. ", count: 42)
            note.tags = ["work/project-\(index % 11)", "topic-\(index % 17)/subtopic", "tag-\(index % 23)"]
            note.isPinned = index % 20 == 0
            notes.append(note)
        }

        // A dedicated trash project gives the model its real trash predicate.
        let trashProject = Project(url: rootURL.appendingPathComponent(".Trash"), label: "Trash")
        trashProject.isTrash = true
        projects.append(trashProject)
        for index in notes.indices where index % 50 == 49 {
            notes[index].project = trashProject
        }

        // Independently derive each folder's expected non-trash subtree total
        // so benchmark correctness does not merely compare a value to itself.
        var expectedSubtreeCounts = [URL: Int]()
        for note in notes where !note.isTrash() {
            expectedSubtreeCounts[note.project.url, default: 0] += 1
        }
        if folderCount > 0 {
            for index in stride(from: folderCount - 1, through: 0, by: -1) {
                let project = projects[index + 1]
                if let parent = project.parent {
                    expectedSubtreeCounts[parent.url, default: 0] += expectedSubtreeCounts[project.url, default: 0]
                }
            }
        }

        storage.defaultProject = defaultProject
        storage.projects = projects
        storage.noteList = notes

        let sidebar = Sidebar()
        sidebar.items = [[
            SidebarItem(name: "Home", type: .Home),
            SidebarItem(name: "All Notes", type: .All),
            SidebarItem(name: "Trash", type: .Trash)
        ]]
        let table = SidebarTableView()
        table.sidebar = sidebar
        UIApplication.controller.sidebarTableView = table

        let nonTrashDailyDates = Set(notes.filter { !$0.isTrash() }.compactMap { dateFormatter.date(from: $0.fileName) }.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        let previousCount = min(14, nonTrashDailyDates.filter { $0 < today }.count)
        return BenchmarkDataset(
            notes: notes,
            projects: projects,
            defaultProject: defaultProject,
            dailyDateKeys: nonTrashDailyDates.count,
            dailyPreviousCount: previousCount,
            expectedSubtreeCounts: expectedSubtreeCounts
        )
    }

    static func validateDateGroupingAndCache() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2040, month: 3, day: 10, hour: 12))!
        let startOfToday = calendar.startOfDay(for: now)
        let project = Project(url: URL(fileURLWithPath: "/tmp/grouping-validation"), label: "Validation")
        let dates = [
            startOfToday.addingTimeInterval(3_600),
            calendar.date(byAdding: .day, value: -1, to: startOfToday)!.addingTimeInterval(3_600),
            calendar.date(byAdding: .day, value: -7, to: startOfToday)!.addingTimeInterval(3_600),
            calendar.date(byAdding: .day, value: -8, to: startOfToday)!.addingTimeInterval(3_600),
            calendar.date(byAdding: .day, value: -31, to: startOfToday)!.addingTimeInterval(3_600)
        ]
        let items = dates.enumerated().map { index, date in
            let note = Note(index: index, project: project, modifiedLocalAt: date, fileName: "validation-\(index)")
            return OverviewNoteItem(id: "validation-\(index)", title: "Validation", preview: "", dateLabel: "", isPinned: false, note: note)
        }
        let labels = groupedByDate(items, now: now, calendar: calendar).map(\.label)
        precondition(Set(labels) == Set(["Today", "Yesterday", "Last 7 days", "Last 30 days", "2040"]), "Date grouping boundaries changed")

        let cacheModel = OverviewModel()
        cacheModel.recentNotes = Array(items.prefix(2))
        precondition(cacheModel.recentDateGroups.reduce(0) { $0 + $1.items.count } == 2, "Recent group cache did not populate")
        cacheModel.recentNotes = [items[4]]
        precondition(cacheModel.recentDateGroups.reduce(0) { $0 + $1.items.count } == 1, "Recent group cache did not invalidate")

        let mutableNote = Note(index: 20, project: project, modifiedLocalAt: Date(), fileName: "mutable")
        let mutableItem = OverviewNoteItem(id: "mutable", title: "Mutable", preview: "", dateLabel: "", isPinned: false, note: mutableNote)
        cacheModel.recentNotes = [mutableItem]
        let todayLabel = cacheModel.recentDateGroups.first?.label
        mutableNote.modifiedLocalAt = calendar.date(byAdding: .day, value: -31, to: startOfToday)!.addingTimeInterval(3_600)
        cacheModel.recentNotes = [mutableItem]
        precondition(cacheModel.recentDateGroups.first?.label != todayLabel, "Date mutation did not refresh cached grouping")
        NotificationCenter.default.post(name: Notification.Name.NSCalendarDayChanged, object: nil)
    }

    static func validateHomeFolderIndex() {
        let storage = Storage.shared()
        let rootURL = URL(fileURLWithPath: "/tmp/home-index-validation")
        let defaultProject = Project(url: rootURL, label: "Default", isDefault: true)
        let visibleRoot = Project(url: rootURL.appendingPathComponent("visible-root"), label: "Visible Root", parent: defaultProject)
        let secondRoot = Project(url: rootURL.appendingPathComponent("second-root"), label: "Second Root", parent: defaultProject)
        let hiddenParent = Project(url: rootURL.appendingPathComponent("hidden-parent"), label: "Hidden Parent", parent: defaultProject)
        hiddenParent.settings.showInSidebar = false
        let hiddenChild = Project(url: rootURL.appendingPathComponent("hidden-child"), label: "Visible Child", parent: hiddenParent)
        let firstNote = Note(index: 30, project: visibleRoot, modifiedLocalAt: Date(), fileName: "first")
        let secondNote = Note(index: 31, project: secondRoot, modifiedLocalAt: Date(), fileName: "second")
        storage.defaultProject = defaultProject
        storage.projects = [defaultProject, visibleRoot, secondRoot, hiddenParent, hiddenChild]
        storage.noteList = [firstNote, secondNote]

        let sidebar = Sidebar()
        sidebar.items = [[SidebarItem(name: "Home", type: .Home)]]
        let table = SidebarTableView()
        table.sidebar = sidebar
        UIApplication.controller.sidebarTableView = table

        let model = HomeLibraryModel()
        model.reload()
        precondition(model.children(of: defaultProject).count == 2, "Default parent child index mismatch")
        precondition(Set(model.children(of: nil).map(\.url)) == Set([hiddenChild.url, visibleRoot.url, secondRoot.url]), "Initial root index mismatch")
        precondition(model.noteCount(for: visibleRoot) == 1, "Initial visible root count mismatch")

        secondRoot.parent = visibleRoot
        model.reload()
        precondition(Set(model.children(of: nil).map(\.url)) == Set([hiddenChild.url, visibleRoot.url]), "Reparented root remained indexed")
        precondition(model.children(of: visibleRoot).map(\.url) == [secondRoot.url], "Reparented child was not indexed")
        precondition(model.noteCount(for: visibleRoot) == 2, "Reparented subtree count mismatch")

        storage.projects = [defaultProject, visibleRoot, hiddenParent, hiddenChild]
        model.reload()
        precondition(!model.children(of: nil).contains(where: { $0.url == secondRoot.url }), "Removed project remained a stale root")
        precondition(!model.children(of: visibleRoot).contains(where: { $0.url == secondRoot.url }), "Removed project remained a stale child")
        precondition(model.noteCount(for: visibleRoot) == 1, "Removed project left a stale subtree count")
    }

    static func validateDailyNotesModel() {
        let storage = Storage.shared()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let today = calendar.startOfDay(for: Date())
        func fileName(daysFromToday: Int) -> String {
            formatter.string(from: calendar.date(byAdding: .day, value: daysFromToday, to: today)!)
        }

        let project = Project(url: URL(fileURLWithPath: "/tmp/daily-validation"), label: "Validation")
        let trashProject = Project(url: URL(fileURLWithPath: "/tmp/daily-validation-trash"), label: "Trash")
        trashProject.isTrash = true
        var previousFileNames = [-1, -2, -3].map { fileName(daysFromToday: $0) }
        if previousFileNames.contains("2024-02-29") {
            previousFileNames = [-10, -11, -12].map { fileName(daysFromToday: $0) }
        }
        let newestFileName = previousFileNames[0]
        let middleFileName = previousFileNames[1]
        let oldestFileName = previousFileNames[2]
        let duplicateFirst = Note(index: 0, project: project, modifiedLocalAt: Date(), fileName: newestFileName)
        let duplicateLast = Note(index: 1, project: project, modifiedLocalAt: Date(), fileName: newestFileName)
        let middle = Note(index: 2, project: project, modifiedLocalAt: Date(), fileName: middleFileName)
        let oldest = Note(index: 3, project: project, modifiedLocalAt: Date(), fileName: oldestFileName)
        let leap = Note(index: 4, project: project, modifiedLocalAt: Date(), fileName: "2024-02-29")
        let invalidDate = Note(index: 5, project: project, modifiedLocalAt: Date(), fileName: "2026-02-30")
        let invalidShape = Note(index: 6, project: project, modifiedLocalAt: Date(), fileName: "2026-2-03")
        let ordinaryName = Note(index: 7, project: project, modifiedLocalAt: Date(), fileName: "Research-2026")
        let suffixName = Note(index: 8, project: project, modifiedLocalAt: Date(), fileName: "2024-02-29.md")
        let trash = Note(index: 9, project: trashProject, modifiedLocalAt: Date(), fileName: fileName(daysFromToday: -4))
        storage.noteList = [duplicateFirst, duplicateLast, middle, oldest, leap, invalidDate, invalidShape, ordinaryName, suffixName, trash]

        let model = DailyNotesModel()
        precondition(model.notesByDay.count == 4, "Daily filename validation count mismatch")
        precondition(model.notesByDay.values.contains(where: { $0 === duplicateLast }), "Duplicate daily filename did not keep the last note")
        precondition(!model.notesByDay.values.contains(where: { $0 === duplicateFirst }), "Duplicate daily filename kept the first note")
        precondition(model.notesByDay.values.contains(where: { $0 === leap }), "Valid leap-day filename was rejected")
        precondition(!model.notesByDay.values.contains(where: { $0 === trash }), "Trash daily note was included")

        model.previousLimit = 2
        precondition(model.previous.count == 2, "Daily previous pagination limit mismatch")
        precondition(model.previous.first?.note === duplicateLast, "Daily previous order mismatch")
        precondition(model.previous.dropFirst().first?.note === middle, "Daily previous pagination order mismatch")

        let replacement = Note(index: 10, project: project, modifiedLocalAt: Date(), fileName: "2024-02-29")
        storage.noteList = [replacement]
        model.reload()
        precondition(model.notesByDay.count == 1 && model.notesByDay.values.first === replacement, "Daily reload did not replace old keys")
        precondition(!model.notesByDay.values.contains(where: { $0 === duplicateLast || $0 === middle || $0 === oldest }), "Daily reload retained stale keys")
    }

    static func run(noteCount: Int, folderCount: Int) -> BenchmarkResult {
        let dataset = makeDataset(noteCount: noteCount, folderCount: folderCount)
        let storage = Storage.shared()
        let model = HomeLibraryModel()
        let homeStats = measure {
            model.reload()
            return model.folders.count + model.starred.count + model.trashCount + model.tags.count
        }

        let expectedTrashCount = dataset.notes.filter { $0.isTrash() }.count
        let expectedNonTrashCount = dataset.notes.count - expectedTrashCount
        precondition(model.folders.count == (folderCount > 0 ? 1 : 0), "Unexpected Home folder root count")
        precondition(model.trashCount == expectedTrashCount, "Trash count mismatch")
        precondition(model.starred.count == dataset.notes.filter { $0.isPinned && !$0.isTrash() }.count, "Starred count mismatch")
        if let root = model.folders.first {
            precondition(root.noteCount == dataset.expectedSubtreeCounts[root.project.url, default: 0], "Root subtree count mismatch")
        }
        for project in dataset.projects where !project.isDefault && !project.isTrash {
            precondition(model.noteCount(for: project) == dataset.expectedSubtreeCounts[project.url, default: 0], "Folder subtree count mismatch")
        }

        let folderStats = measure {
            var checksum = 0
            for project in dataset.projects where !project.isDefault && !project.isTrash {
                checksum += model.children(of: project).count
                checksum += model.hasChildren(project) ? 1 : 0
                checksum += model.noteCount(for: project)
                checksum += model.node(for: project, depth: 0).noteCount
            }
            return checksum
        }

        let daily = DailyNotesModel()
        let dailyReloadStats = measure {
            daily.reload()
            return daily.notesByDay.count
        }
        let previousStats = measure { daily.previous.count }

        let overviewItems = storage.noteList.filter { !$0.isTrash() }.map {
            OverviewNoteItem(id: $0.url.absoluteString, title: $0.title, preview: $0.preview, dateLabel: "benchmark", isPinned: $0.isPinned, note: $0)
        }
        let groupedStats = measure {
            groupedByDate(overviewItems).reduce(0) { $0 + $1.items.count }
        }
        let overviewModel = OverviewModel()
        overviewModel.recentNotes = overviewItems
        overviewModel.folderNotes = overviewItems
        let cachedGroupStats = measure {
            var checksum = 0
            for _ in 0..<8 {
                checksum += overviewModel.recentDateGroups.reduce(0) { $0 + $1.items.count }
                checksum += overviewModel.folderDateGroups.reduce(0) { $0 + $1.items.count }
            }
            return checksum
        }

        precondition(daily.notesByDay.count == dataset.dailyDateKeys, "Daily date key count mismatch")
        precondition(daily.previous.count == dataset.dailyPreviousCount, "Daily previous count mismatch")
        precondition(groupedByDate(overviewItems).reduce(0) { $0 + $1.items.count } == expectedNonTrashCount, "Grouped item count mismatch")

        let trashCount = expectedTrashCount
        let nonTrashCount = expectedNonTrashCount
        let correctness = Correctness(
            expectedNotes: noteCount,
            expectedNonTrashNotes: nonTrashCount,
            expectedTrashNotes: trashCount,
            expectedProjects: folderCount,
            expectedDailyDateKeys: dataset.dailyDateKeys,
            homeFolders: model.folders.count,
            homeStarred: model.starred.count,
            homeTrashCount: model.trashCount,
            dailyDateKeys: daily.notesByDay.count,
            dailyPreviousCount: daily.previous.count,
            folderLookupProjects: dataset.projects.filter { !$0.isDefault && !$0.isTrash }.count,
            groupedItems: groupedByDate(overviewItems).reduce(0) { $0 + $1.items.count },
            cachedGroupedItems: overviewModel.recentDateGroups.reduce(0) { $0 + $1.items.count }
        )
        return BenchmarkResult(
            noteCount: noteCount,
            folderCount: folderCount,
            metrics: [
                "homeReload": homeStats,
                "folderNodeLookups": folderStats,
                "dailyReload": dailyReloadStats,
                "dailyPreviousGetter": previousStats,
                "groupedByDate": groupedStats,
                "cachedGroupAccess": cachedGroupStats
            ],
            correctness: correctness
        )
    }

    static func main() {
        validateDateGroupingAndCache()
        validateDailyNotesModel()
        validateHomeFolderIndex()
        let results = [
            run(noteCount: 5, folderCount: 2),
            run(noteCount: 5, folderCount: 250),
            run(noteCount: 5_000, folderCount: 2),
            run(noteCount: 5_000, folderCount: 250)
        ]
        let document = BenchmarkDocument(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            toolchain: "Apple Swift 6.2.4, macOS arm64",
            warmups: 3,
            samples: 15,
            clock: "ContinuousClock",
            results: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try! encoder.encode(document)
        print(String(decoding: data, as: UTF8.self))
    }
}

@main
struct Main {
    static func main() async {
        await MainActor.run { BenchmarkRunner.main() }
    }
}
SWIFT

CLANG_MODULE_CACHE_PATH="$module_cache_dir" SWIFT_MODULECACHE_PATH="$module_cache_dir" \
    swiftc -disable-sandbox -parse-as-library -O "$work_dir/runner.swift" -o "$work_dir/fsnotes-performance"
"$work_dir/fsnotes-performance"
