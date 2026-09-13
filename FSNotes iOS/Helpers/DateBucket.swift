//
//  DateBucket.swift
//  FSNotes iOS
//
//  Craft-style relative date groups used by list screens
//  ("Today", "Yesterday", "Last 7 days", "Last 30 days", then years).
//

import Foundation

enum DateBucket: Hashable, Comparable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case year(Int)
    case undated

    static func bucket(for date: Date?, calendar: Calendar = .current, now: Date = Date()) -> DateBucket {
        guard let date else { return .undated }

        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days >= 0 && days < 7 { return .last7Days }
        if days >= 0 && days < 30 { return .last30Days }

        return .year(calendar.component(.year, from: date))
    }

    var title: String {
        switch self {
        case .today: return NSLocalizedString("Today", comment: "Date group")
        case .yesterday: return NSLocalizedString("Yesterday", comment: "Date group")
        case .last7Days: return NSLocalizedString("Last 7 days", comment: "Date group")
        case .last30Days: return NSLocalizedString("Last 30 days", comment: "Date group")
        case .year(let year): return String(year)
        case .undated: return NSLocalizedString("Undated", comment: "Date group")
        }
    }

    private var order: Int {
        switch self {
        case .today: return 0
        case .yesterday: return 1
        case .last7Days: return 2
        case .last30Days: return 3
        case .year(let year): return 10_000 - year
        case .undated: return 20_000
        }
    }

    static func < (lhs: DateBucket, rhs: DateBucket) -> Bool {
        lhs.order < rhs.order
    }
}
