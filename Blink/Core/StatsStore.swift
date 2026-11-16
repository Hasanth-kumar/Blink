import Foundation
import Combine

/// Converts between dates and the "yyyy-MM-dd" keys statistics are stored under.
enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(for key: String) -> Date? {
        formatter.date(from: key)
    }
}

/// One day of break history.
struct DayStats: Codable, Identifiable, Equatable {
    var day: String
    var taken: Int
    var skipped: Int
    var snoozed: Int
    var naturalBreaks: Int
    var restSeconds: Double

    var id: String { day }

    init(day: String, taken: Int = 0, skipped: Int = 0, snoozed: Int = 0, naturalBreaks: Int = 0, restSeconds: Double = 0) {
        self.day = day
        self.taken = taken
        self.skipped = skipped
        self.snoozed = snoozed
        self.naturalBreaks = naturalBreaks
        self.restSeconds = restSeconds
    }

    var date: Date {
        DayKey.date(for: day) ?? Date.distantPast
    }
}

enum StatEvent {
    case taken(seconds: TimeInterval)
    case skipped
    case snoozed
    case natural(seconds: TimeInterval)
}

/// Break history, kept as a small JSON file in Application Support.
@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var days: [String: DayStats] = [:]

    private let fileURL: URL
    private let retentionDays = 400

    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = base
                .appendingPathComponent("Blink", isDirectory: true)
                .appendingPathComponent("stats.json")
        }
        load()
    }

    func record(_ event: StatEvent, at date: Date = Date()) {
        let key = DayKey.key(for: date)
        var entry = days[key] ?? DayStats(day: key)
        switch event {
        case .taken(let seconds):
            entry.taken += 1
            entry.restSeconds += max(0, seconds)
        case .skipped:
            entry.skipped += 1
        case .snoozed:
            entry.snoozed += 1
        case .natural:
            entry.naturalBreaks += 1
        }
        days[key] = entry
        prune()
        save()
    }

    /// The most recent `count` days, oldest first, with empty days filled in.
    func lastDays(_ count: Int, endingAt end: Date = Date()) -> [DayStats] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: end)
        var result: [DayStats] = []
        var offset = max(count, 1) - 1
        while offset >= 0 {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                let key = DayKey.key(for: date)
                result.append(days[key] ?? DayStats(day: key))
            }
            offset -= 1
        }
        return result
    }

    func reset() {
        days = [:]
        save()
    }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([DayStats].self, from: data) else { return }
        var loaded: [String: DayStats] = [:]
        for entry in entries {
            loaded[entry.day] = entry
        }
        days = loaded
    }

    private func save() {
        let entries = days.values.sorted { $0.day < $1.day }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Blink: could not save statistics – %@", error.localizedDescription)
        }
    }

    private func prune() {
        guard days.count > retentionDays else { return }
        let keep = Set(days.keys.sorted().suffix(retentionDays))
        days = days.filter { keep.contains($0.key) }
    }
}
