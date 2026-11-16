import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var ui: SettingsUIState

    var body: some View {
        let days = stats.lastDays(ui.statsRange)
        let taken = days.reduce(0) { $0 + $1.taken }
        let skipped = days.reduce(0) { $0 + $1.skipped }
        let snoozed = days.reduce(0) { $0 + $1.snoozed }
        let rest = days.reduce(0.0) { $0 + $1.restSeconds }
        let today = days.last

        return SettingsPage(title: "Stats") {
            Section("Today") {
                LabeledContent("Breaks taken", value: "\(today?.taken ?? 0)")
                LabeledContent("Breaks skipped", value: "\(today?.skipped ?? 0)")
                LabeledContent("Time away from the keyboard", value: "\(today?.naturalBreaks ?? 0) natural breaks")
            }

            Section {
                Picker("Period", selection: $ui.statsRange) {
                    Text("Last 7 days").tag(7)
                    Text("Last 30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                chart(for: days)
                    .frame(height: 220)
                    .padding(.vertical, 6)
            } header: {
                Text("Breaks taken and skipped")
            }

            Section("Totals for this period") {
                LabeledContent("Taken", value: "\(taken)")
                LabeledContent("Skipped", value: "\(skipped)")
                LabeledContent("Snoozed", value: "\(snoozed)")
                LabeledContent("Follow-through", value: StatsView.percentage(taken: taken, skipped: skipped))
                LabeledContent("Time resting", value: StatsView.duration(rest))
            }

            Section {
                Button("Reset Statistics…", role: .destructive) {
                    ui.confirmingStatsReset = true
                }
                .confirmationDialog(
                    "Erase all break statistics?",
                    isPresented: $ui.confirmingStatsReset,
                    titleVisibility: .visible
                ) {
                    Button("Erase", role: .destructive) {
                        stats.reset()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    private func chart(for days: [DayStats]) -> some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Breaks", day.taken)
                )
                .foregroundStyle(by: .value("Outcome", "Taken"))

                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Breaks", day.skipped)
                )
                .foregroundStyle(by: .value("Outcome", "Skipped"))
            }
        }
        .chartForegroundStyleScale([
            "Taken": Color.accentColor,
            "Skipped": Color.gray.opacity(0.45)
        ])
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .accessibilityLabel("Breaks taken and skipped per day")
    }

    private static func percentage(taken: Int, skipped: Int) -> String {
        let total = taken + skipped
        guard total > 0 else { return "–" }
        let value = Int((Double(taken) / Double(total) * 100).rounded())
        return "\(value)%"
    }

    private static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        }
        if minutes > 0 {
            return "\(minutes) min"
        }
        return "\(total) sec"
    }
}
