import SwiftUI

struct ScheduleSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsPage(title: "Break Schedule") {
            Section("Breaks") {
                StepperRow(title: "Work for", value: $settings.workMinutes, range: 1...120, unit: "min")
                StepperRow(title: "Then rest for", value: $settings.shortBreakSeconds, range: 5...300, step: 5, unit: "sec")
                Hint("The default follows the 20-20-20 rule: every 20 minutes, look at something 20 feet (6 m) away for 20 seconds.")
            }

            Section("Long breaks") {
                Toggle("Take a longer break now and then", isOn: $settings.longBreakEnabled)
                if settings.longBreakEnabled {
                    StepperRow(title: "Long break every", value: $settings.longBreakEvery, range: 2...12, unit: "breaks")
                    StepperRow(title: "Long break lasts", value: $settings.longBreakMinutes, range: 1...30, unit: "min")
                }
            }

            Section("Heads-up") {
                Toggle("Show a heads-up before each break", isOn: $settings.warningEnabled)
                if settings.warningEnabled {
                    StepperRow(title: "Show it", value: $settings.warningLeadSeconds, range: 10...300, step: 10, unit: "sec before")
                    Toggle("Compact heads-up that expands on hover", isOn: $settings.warningCompact)
                }
                Toggle("Limit snoozes", isOn: $settings.snoozeLimitEnabled)
                if settings.snoozeLimitEnabled {
                    StepperRow(title: "Snoozes allowed per break", value: $settings.snoozeLimit, range: 1...10, unit: settings.snoozeLimit == 1 ? "snooze" : "snoozes")
                    Toggle("Show how many snoozes are left", isOn: $settings.showSnoozesLeft)
                }
            }

            Section("Office hours") {
                Toggle("Only remind me during office hours", isOn: $settings.officeHoursEnabled)
                if settings.officeHoursEnabled {
                    LabeledContent("Days") {
                        weekdayPicker
                    }
                    DatePicker("From", selection: startBinding, displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: endBinding, displayedComponents: .hourAndMinute)
                    Hint("If “Until” is earlier than “From”, the hours run overnight into the next morning.")
                }
            }
        }
    }

    // MARK: Office-hour helpers

    /// Weekday numbers (1 = Sunday) in the order the user's calendar shows them.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private var weekdayPicker: some View {
        let symbols = Calendar.current.shortWeekdaySymbols
        return HStack(spacing: 4) {
            ForEach(orderedWeekdays, id: \.self) { day in
                Toggle(isOn: dayBinding(day)) {
                    Text(day - 1 < symbols.count ? symbols[day - 1] : "\(day)")
                        .font(.system(size: 11))
                }
                .toggleStyle(.button)
            }
        }
    }

    private func dayBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { settings.officeDays.contains(day) },
            set: { isOn in
                var days = Set(settings.officeDays)
                if isOn {
                    days.insert(day)
                } else {
                    days.remove(day)
                }
                settings.officeDays = days.sorted()
            }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { ScheduleSettingsView.date(fromMinutes: settings.officeStartMinute) },
            set: { settings.officeStartMinute = ScheduleSettingsView.minutes(from: $0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { ScheduleSettingsView.date(fromMinutes: settings.officeEndMinute) },
            set: { settings.officeEndMinute = ScheduleSettingsView.minutes(from: $0) }
        )
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: today) ?? today
    }

    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
