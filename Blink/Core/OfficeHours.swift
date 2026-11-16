import Foundation

/// The days and hours during which Blink is allowed to schedule breaks.
struct OfficeHours: Equatable {
    var enabled: Bool = false
    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    /// Minutes after midnight.
    var startMinute: Int = 9 * 60
    var endMinute: Int = 18 * 60
    var calendar: Calendar = .current

    /// True when breaks may run at `date`. Always true while office hours are switched off.
    func contains(_ date: Date) -> Bool {
        guard enabled else { return true }
        guard !weekdays.isEmpty else { return false }

        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let weekday = parts.weekday ?? 1
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        if startMinute == endMinute {
            // Same start and end means "all day" on the chosen days.
            return weekdays.contains(weekday)
        }
        if startMinute < endMinute {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        // Overnight window such as 22:00 – 06:00. The early-morning part belongs
        // to the shift that started the previous day.
        let previousDay = weekday == 1 ? 7 : weekday - 1
        return (weekdays.contains(weekday) && minute >= startMinute)
            || (weekdays.contains(previousDay) && minute < endMinute)
    }

    /// The next moment office hours begin after `date`, if there is one.
    func nextStart(after date: Date) -> Date? {
        guard enabled, !weekdays.isEmpty else { return nil }
        let startOfToday = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard weekdays.contains(weekday) else { continue }
            guard let candidate = calendar.date(
                bySettingHour: startMinute / 60,
                minute: startMinute % 60,
                second: 0,
                of: day
            ) else { continue }
            if candidate > date { return candidate }
        }
        return nil
    }
}
