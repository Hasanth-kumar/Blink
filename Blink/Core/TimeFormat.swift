import Foundation

/// Small formatting helpers shared by the menu bar, the heads-up and the break screen.
enum TimeFormat {
    /// "12:34", or "1:02:03" past the hour. Rounds up, so "0:01" is shown until time is really up.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "12m" – whole minutes, rounded up.
    static func minutes(_ interval: TimeInterval) -> String {
        let total = max(0, interval)
        let minutes = Int((total / 60).rounded(.up))
        return "\(minutes)m"
    }

    /// "20 seconds", "1 minute", "5 minutes".
    static func spoken(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 || seconds % 60 != 0 {
            if seconds >= 120 {
                let minutes = seconds / 60
                let rest = seconds % 60
                return "\(minutes) min \(rest) sec"
            }
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }
        let minutes = seconds / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// "3:45 PM" in the user's locale.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "3:45 PM", "tomorrow at 9:00 AM" or "Mon 9:00 AM".
    static func dayAndTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return time(date)
        }
        if calendar.isDateInTomorrow(date) {
            return "tomorrow at \(time(date))"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
