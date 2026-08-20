import Foundation

struct DayGroup: Identifiable, Equatable {
    var id: Date { day }

    let day: Date
    var dumps: [Dump]

    init(day: Date, dumps: [Dump]) {
        self.day = day
        self.dumps = dumps.sorted { $0.createdAt < $1.createdAt }
    }

    var dayLabel: String {
        Self.formattedLabel(for: day)
    }

    static func formattedLabel(for date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current

        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        let isCurrentYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")

        if isCurrentYear {
            let daysApart = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
            if daysApart < 7 {
                formatter.dateFormat = "EEEE, MMMM d"
            } else {
                formatter.dateFormat = "MMMM d"
            }
        } else {
            formatter.dateFormat = "MMMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    static func grouped(from dumps: [Dump], calendar: Calendar = Calendar.current) -> [DayGroup] {
        let grouped = Dictionary(grouping: dumps) { dump in
            calendar.startOfDay(for: dump.createdAt)
        }
        return grouped
            .map { DayGroup(day: $0.key, dumps: $0.value) }
            .sorted { $0.day > $1.day }
    }
}
