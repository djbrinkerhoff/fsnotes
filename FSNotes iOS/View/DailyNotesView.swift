//
//  DailyNotesView.swift
//  FSNotes iOS
//
//  Craft-style daily notes: a vertical timeline of days starting today, each
//  with its note (or a create button), plus previous days on demand.
//

import SwiftUI

@MainActor
@Observable
final class DailyNotesModel {
    struct Day: Identifiable {
        var id: Date { date }
        var date: Date
        var note: Note?
    }

    var upcomingDays = 7
    var showsPreviousDays = false
    var previousLimit = 14

    private(set) var notesByDay = [Date: Note]()
    private var dailyDateFormatter: DateFormatter?
    private var dailyDateFormatterTimeZone: TimeZone?
    private var orderedDateKeys = [Date]()

    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .fsnotesLibraryDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() {
        let calendar = Calendar.current
        let formatter = dailyDateFormatter(for: calendar)

        var map = [Date: Note]()
        for note in Storage.shared().noteList where !note.isTrash() {
            guard Self.hasDailyDateShape(note.fileName),
                  let date = formatter.date(from: note.fileName),
                  formatter.string(from: date) == note.fileName else { continue }
            map[calendar.startOfDay(for: date)] = note
        }
        notesByDay = map
        orderedDateKeys = map.keys.sorted(by: >)
    }

    var today: Date { Calendar.current.startOfDay(for: Date()) }

    /// Today and the next `upcomingDays` days.
    var upcoming: [Day] {
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: Date())
        return (0..<(upcomingDays + 1)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: currentDay) else { return nil }
            return Day(date: date, note: notesByDay[date])
        }
    }

    /// Earlier days that have a note, newest first.
    var previous: [Day] {
        let currentDay = Calendar.current.startOfDay(for: Date())
        return orderedDateKeys
            .drop(while: { $0 >= currentDay })
            .prefix(previousLimit)
            .map { Day(date: $0, note: notesByDay[$0]) }
    }

    var hasPrevious: Bool {
        let currentDay = Calendar.current.startOfDay(for: Date())
        return orderedDateKeys.last.map { $0 < currentDay } ?? false
    }

    private func dailyDateFormatter(for calendar: Calendar) -> DateFormatter {
        if let dailyDateFormatter, dailyDateFormatterTimeZone == calendar.timeZone {
            return dailyDateFormatter
        }

        var parsingCalendar = Calendar(identifier: .gregorian)
        parsingCalendar.timeZone = calendar.timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = parsingCalendar
        formatter.timeZone = parsingCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        dailyDateFormatter = formatter
        dailyDateFormatterTimeZone = calendar.timeZone
        return formatter
    }

    private static func hasDailyDateShape(_ fileName: String) -> Bool {
        guard fileName.utf8.count == 10 else { return false }
        for (index, byte) in fileName.utf8.enumerated() {
            if index == 4 || index == 7 {
                guard byte == 45 else { return false }
            } else {
                guard byte >= 48, byte <= 57 else { return false }
            }
        }
        return true
    }
}

struct DailyNotesView: View {
    @Bindable var model: DailyNotesModel
    var open: (Date) -> Void

    @State private var isJumping = false
    @State private var jumpDate = Date()

    var body: some View {
        List {
            if model.hasPrevious {
                Section {
                    Button {
                        withAnimation(.snappy) { model.showsPreviousDays.toggle() }
                    } label: {
                        Label(
                            model.showsPreviousDays
                                ? NSLocalizedString("Hide Previous Days", comment: "Daily notes")
                                : NSLocalizedString("Show Previous Days", comment: "Daily notes"),
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(SwiftUI.Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }

                if model.showsPreviousDays {
                    ForEach(model.previous) { day in
                        DailyDaySection(day: day, isToday: false, open: open)
                    }
                }
            }

            ForEach(model.upcoming) { day in
                DailyDaySection(day: day, isToday: Calendar.current.isDateInToday(day.date), open: open)
            }
        }
        .listStyle(.plain)
        .listRowBackground(SwiftUI.Color.clear)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("Daily Notes", comment: ""))
        .tint(SwiftUI.Color(uiColor: .label))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        jumpDate = Date()
                        isJumping = true
                    } label: {
                        Label(NSLocalizedString("Jump To Day", comment: "Daily notes"), systemImage: "calendar")
                    }
                    Button {
                        withAnimation(.snappy) { model.showsPreviousDays.toggle() }
                    } label: {
                        Label(
                            model.showsPreviousDays
                                ? NSLocalizedString("Hide Previous Days", comment: "Daily notes")
                                : NSLocalizedString("Show Previous Days", comment: "Daily notes"),
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                } label: {
                    Label(NSLocalizedString("More", comment: ""), systemImage: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isJumping) {
            NavigationStack {
                VStack {
                    DatePicker(NSLocalizedString("Day", comment: "Daily notes"), selection: $jumpDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    Spacer()
                }
                .navigationTitle(NSLocalizedString("Jump To Day", comment: "Daily notes"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("Cancel", comment: "")) { isJumping = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NSLocalizedString("Open", comment: "Daily notes")) {
                            isJumping = false
                            open(Calendar.current.startOfDay(for: jumpDate))
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// One day in the timeline: "Sep 13" + "Today · Sunday", then the note preview
/// or a "Create Daily Note" button.
struct DailyDaySection: View {
    var day: DailyNotesModel.Day
    var isToday: Bool
    var open: (Date) -> Void

    private var relative: String? {
        let calendar = Calendar.current
        if calendar.isDateInToday(day.date) { return NSLocalizedString("Today", comment: "Daily notes") }
        if calendar.isDateInTomorrow(day.date) { return NSLocalizedString("Tomorrow", comment: "Daily notes") }
        if calendar.isDateInYesterday(day.date) { return NSLocalizedString("Yesterday", comment: "Daily notes") }
        return nil
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    dayHeading
                    Spacer(minLength: 0)
                    Menu {
                        Button {
                            open(day.date)
                        } label: {
                            Label(day.note == nil
                                  ? NSLocalizedString("Create Daily Note", comment: "Daily notes")
                                  : NSLocalizedString("Open Daily Note", comment: "Daily notes"),
                                  systemImage: "doc.text")
                        }
                    } label: {
                        Label(NSLocalizedString("Day options", comment: "Daily notes"), systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(NSLocalizedString("Day options", comment: "Daily notes"))
                }

                Divider()

                if let note = day.note {
                    Button {
                        open(day.date)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            DocumentGlyph()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.getTitle() ?? note.getShortTitle())
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if !note.preview.isEmpty {
                                    Text(note.preview)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        open(day.date)
                    } label: {
                        Label(NSLocalizedString("Create Daily Note", comment: "Daily notes"), systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(SwiftUI.Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .opacity(isToday ? 1 : 0.8)
                }
            }
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            .listRowBackground(SwiftUI.Color.clear)
        }
        .listSectionSeparator(.hidden)
    }

    private var dayHeading: some View {
        ViewThatFits(in: .horizontal) {
            if !isToday {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    dateLabel
                    weekdayLabel
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                dateLabel
                weekdayLabel
            }
        }
    }

    private var dateLabel: some View {
        Text(day.date, format: .dateTime.month(.abbreviated).day())
            .font(isToday ? .title.bold() : .headline)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var weekdayLabel: some View {
        HStack(spacing: 4) {
            if let relative {
                Text(relative)
                    .fontWeight(.semibold)
                    .foregroundStyle(isToday ? AnyShapeStyle(SwiftUI.Color.blue) : AnyShapeStyle(.secondary))
                Text("·")
            }
            Text(day.date, format: .dateTime.weekday(.wide))
        }
        .font(.body)
        .foregroundStyle(.secondary)
    }
}
