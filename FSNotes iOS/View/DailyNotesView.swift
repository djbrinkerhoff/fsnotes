//
//  DailyNotesView.swift
//  FSNotes iOS
//
//  Craft-style daily notes: a date header with day navigation, a week strip,
//  and the list of days that already have a note.
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

    var selectedDate = Calendar.current.startOfDay(for: Date())
    var existing = [Day]()

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

    var selectedNote: Note? {
        UIApplication.getVC().dailyNote(for: selectedDate)
    }

    var weekDays: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    func reload() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var days = [Day]()
        for note in Storage.shared().noteList where !note.isTrash() {
            if let date = formatter.date(from: note.fileName) {
                days.append(Day(date: Calendar.current.startOfDay(for: date), note: note))
            }
        }

        existing = days.sorted { $0.date > $1.date }
    }

    func hasNote(on date: Date) -> Bool {
        existing.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func shift(days: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = Calendar.current.startOfDay(for: date)
        }
    }

    func shift(weeks: Int) {
        shift(days: weeks * 7)
    }
}

struct DailyNotesView: View {
    @Bindable var model: DailyNotesModel
    var open: (Date) -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(model.selectedDate) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    dateHeader
                    weekStrip
                    openButton
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }

            if !model.existing.isEmpty {
                Section {
                    ForEach(model.existing) { day in
                        Button {
                            open(day.date)
                        } label: {
                            HStack(spacing: 12) {
                                SwiftUI.Image(systemName: "calendar")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.tint)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                        .font(.body.weight(.semibold))
                                    if let preview = day.note?.preview, !preview.isEmpty {
                                        Text(preview)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                SwiftUI.Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HomeSectionHeader(title: NSLocalizedString("Previous Days", comment: "Daily notes section"))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color(uiColor: .systemBackground))
        .navigationTitle(NSLocalizedString("Daily Notes", comment: ""))
        .tint(SwiftUI.Color(uiColor: .mainTheme))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(NSLocalizedString("Today", comment: "Daily notes")) {
                    withAnimation(.snappy) {
                        model.selectedDate = Calendar.current.startOfDay(for: Date())
                    }
                }
                .disabled(isToday)
            }
        }
    }

    private var dateHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedDate, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 34, weight: .bold))
                Text(model.selectedDate, format: .dateTime.weekday(.wide).year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Button(NSLocalizedString("Previous day", comment: ""), systemImage: "chevron.left") {
                    withAnimation(.snappy) { model.shift(days: -1) }
                }
                Button(NSLocalizedString("Next day", comment: ""), systemImage: "chevron.right") {
                    withAnimation(.snappy) { model.shift(days: 1) }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(model.weekDays, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: model.selectedDate)
                Button {
                    withAnimation(.snappy) { model.selectedDate = day }
                } label: {
                    VStack(spacing: 6) {
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                        Text(day, format: .dateTime.day())
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        Circle()
                            .fill(model.hasNote(on: day)
                                  ? (isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                                  : AnyShapeStyle(.clear))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(SwiftUI.Color(uiColor: .tertiarySystemFill)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                withAnimation(.snappy) { model.shift(weeks: value.translation.width < 0 ? 1 : -1) }
            }
        )
    }

    private var openButton: some View {
        Button {
            open(model.selectedDate)
        } label: {
            Label(
                model.selectedNote == nil
                    ? (isToday
                        ? NSLocalizedString("Start Today's Note", comment: "Daily notes")
                        : NSLocalizedString("Create Note for This Day", comment: "Daily notes"))
                    : NSLocalizedString("Open Note", comment: "Daily notes"),
                systemImage: model.selectedNote == nil ? "square.and.pencil" : "doc.text"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
