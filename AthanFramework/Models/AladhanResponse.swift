import Foundation

/// Top-level response from the Aladhan calendar API.
/// Endpoint: GET /v1/calendar/{year}/{month}?latitude=...&longitude=...&method=...
struct AladhanCalendarResponse: Codable {
    let code: Int
    let status: String
    let data: [AladhanDayData]
}

struct AladhanDayData: Codable {
    let timings: AladhanTimings
    let date: AladhanDate
    let meta: AladhanMeta
}

struct AladhanTimings: Codable {
    let Fajr: String
    let Sunrise: String
    let Dhuhr: String
    let Asr: String
    let Sunset: String
    let Maghrib: String
    let Isha: String
    let Imsak: String
    let Midnight: String
    let Firstthird: String?
    let Lastthird: String?

    /// Parses a time string like "05:23 (EET)" into a Date for the given calendar day.
    static func parseTime(_ timeString: String, on date: Date, timezone: TimeZone) -> Date? {
        // Strip timezone annotation like " (EET)" if present
        let cleaned = timeString.components(separatedBy: " (").first ?? timeString

        let parts = cleaned.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var timeComponents = DateComponents()
        timeComponents.year = components.year
        timeComponents.month = components.month
        timeComponents.day = components.day
        timeComponents.hour = hour
        timeComponents.minute = minute
        timeComponents.second = 0
        timeComponents.timeZone = timezone

        return calendar.date(from: timeComponents)
    }
}

struct AladhanDate: Codable {
    let readable: String
    let timestamp: String
    let gregorian: AladhanGregorianDate
    let hijri: AladhanHijriDate
}

struct AladhanGregorianDate: Codable {
    let date: String
    let format: String
    let day: String
    let weekday: AladhanWeekday
    let month: AladhanMonth
    let year: String
}

struct AladhanHijriDate: Codable {
    let date: String
    let format: String
    let day: String
    let weekday: AladhanWeekday
    let month: AladhanMonth
    let year: String
}

struct AladhanWeekday: Codable {
    let en: String
    let ar: String?
}

struct AladhanMonth: Codable {
    let number: Int
    let en: String
    let ar: String?
}

struct AladhanMeta: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let method: AladhanMethod
}

struct AladhanMethod: Codable {
    let id: Int
    let name: String
}
