import Foundation
import SwiftData
import Observation

/// Fetches and caches prayer times from the Aladhan API.
///
/// Inject into the SwiftUI environment so views can access prayer data:
/// ```swift
/// @Environment(PrayerTimeService.self) var prayerService
/// ```
@Observable
@MainActor
final class PrayerTimeService {

    // MARK: - State

    private(set) var isLoading = false
    private(set) var lastError: Error?

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let session: URLSession

    init(modelContext: ModelContext, session: URLSession = .shared) {
        self.modelContext = modelContext
        self.session = session
    }

    // MARK: - Public API

    /// Fetches an entire month of prayer times from the Aladhan API and persists them to SwiftData.
    /// - Returns: The array of `DailyPrayerTimes` that were saved.
    @discardableResult
    func fetchMonth(
        year: Int,
        month: Int,
        latitude: Double,
        longitude: Double,
        method: CalculationMethod,
        school: AsrSchool,
        timezone: String
    ) async throws -> [DailyPrayerTimes] {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let url = try buildURL(
            year: year,
            month: month,
            latitude: latitude,
            longitude: longitude,
            method: method,
            school: school,
            timezone: timezone
        )

        let response: AladhanCalendarResponse
        do {
            let (data, httpResponse) = try await session.data(from: url)
            guard let status = httpResponse as? HTTPURLResponse,
                  (200...299).contains(status.statusCode) else {
                throw PrayerTimeServiceError.badServerResponse
            }
            response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw urlError
        } catch {
            lastError = error
            throw error
        }

        guard response.code == 200 else {
            let err = PrayerTimeServiceError.apiError(code: response.code, status: response.status)
            lastError = err
            throw err
        }

        let tz = TimeZone(identifier: timezone) ?? .current

        // Delete any existing cached entries for this month/location/method so we don't duplicate.
        deleteCachedMonth(
            year: year,
            month: month,
            latitude: latitude,
            longitude: longitude,
            method: method,
            timezone: timezone
        )

        var results: [DailyPrayerTimes] = []

        for dayData in response.data {
            guard let dayDate = gregorianDate(from: dayData.date.gregorian, timezone: tz) else {
                continue
            }

            let entry = DailyPrayerTimes()
            entry.date = dayDate
            entry.latitude = latitude
            entry.longitude = longitude
            entry.timezone = timezone
            entry.calculationMethod = method.rawValue
            entry.fajr = AladhanTimings.parseTime(dayData.timings.Fajr, on: dayDate, timezone: tz)
            entry.sunrise = AladhanTimings.parseTime(dayData.timings.Sunrise, on: dayDate, timezone: tz)
            entry.dhuhr = AladhanTimings.parseTime(dayData.timings.Dhuhr, on: dayDate, timezone: tz)
            entry.asr = AladhanTimings.parseTime(dayData.timings.Asr, on: dayDate, timezone: tz)
            entry.maghrib = AladhanTimings.parseTime(dayData.timings.Maghrib, on: dayDate, timezone: tz)
            entry.isha = AladhanTimings.parseTime(dayData.timings.Isha, on: dayDate, timezone: tz)
            entry.hijriDate = dayData.date.hijri.date
            entry.gregorianDate = dayData.date.gregorian.date
            entry.fetchedAt = Date()

            modelContext.insert(entry)
            results.append(entry)
        }

        try modelContext.save()
        return results
    }

    /// Convenience: fetches the current month's prayer times.
    @discardableResult
    func fetchToday(
        latitude: Double,
        longitude: Double,
        method: CalculationMethod,
        school: AsrSchool,
        timezone: String
    ) async throws -> [DailyPrayerTimes] {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        return try await fetchMonth(
            year: year,
            month: month,
            latitude: latitude,
            longitude: longitude,
            method: method,
            school: school,
            timezone: timezone
        )
    }

    /// Returns cached prayer times for the given date, or `nil` if nothing is cached.
    func getCachedTimes(for date: Date) -> DailyPrayerTimes? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = #Predicate<DailyPrayerTimes> { entry in
            entry.date >= startOfDay && entry.date < endOfDay
        }

        var descriptor = FetchDescriptor<DailyPrayerTimes>(predicate: predicate)
        descriptor.fetchLimit = 1

        return try? modelContext.fetch(descriptor).first
    }

    /// High-level method that returns today's times, using cache first and falling back to a network fetch.
    func todayTimes(
        latitude: Double,
        longitude: Double,
        method: CalculationMethod,
        school: AsrSchool,
        timezone: String
    ) async -> DailyPrayerTimes? {
        // Try cache first
        if let cached = getCachedTimes(for: Date()) {
            return cached
        }

        // Fetch from network, return cached data on failure
        do {
            let results = try await fetchToday(
                latitude: latitude,
                longitude: longitude,
                method: method,
                school: school,
                timezone: timezone
            )
            return results.first { Calendar.current.isDateInToday($0.date) }
        } catch {
            // Network failed — return whatever we have cached (may still be nil)
            return getCachedTimes(for: Date())
        }
    }

    // MARK: - Private Helpers

    private func buildURL(
        year: Int,
        month: Int,
        latitude: Double,
        longitude: Double,
        method: CalculationMethod,
        school: AsrSchool,
        timezone: String
    ) throws -> URL {
        let base = AppConstants.API.aladhanBaseURL + AppConstants.API.calendarEndpoint
        let path = "\(base)/\(year)/\(month)"

        guard var components = URLComponents(string: path) else {
            throw PrayerTimeServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "method", value: String(method.rawValue)),
            URLQueryItem(name: "school", value: String(school.rawValue)),
            URLQueryItem(name: "timezonestring", value: timezone),
        ]

        guard let url = components.url else {
            throw PrayerTimeServiceError.invalidURL
        }
        return url
    }

    /// Parses the Aladhan gregorian date object into a `Date` at midnight in the given timezone.
    private func gregorianDate(from greg: AladhanGregorianDate, timezone tz: TimeZone) -> Date? {
        // greg.date is "DD-MM-YYYY"
        let parts = greg.date.split(separator: "-")
        guard parts.count == 3,
              let day = Int(parts[0]),
              let month = Int(parts[1]),
              let year = Int(parts[2]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Removes previously cached entries for a given month so they can be replaced by fresh data.
    private func deleteCachedMonth(
        year: Int,
        month: Int,
        latitude: Double,
        longitude: Double,
        method: CalculationMethod,
        timezone: String
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current

        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return
        }

        let methodRaw = method.rawValue
        let predicate = #Predicate<DailyPrayerTimes> { entry in
            entry.date >= start
                && entry.date < end
                && entry.calculationMethod == methodRaw
                && entry.timezone == timezone
        }

        do {
            try modelContext.delete(model: DailyPrayerTimes.self, where: predicate)
        } catch {
            // Non-fatal — duplicate entries may exist temporarily
        }
    }
}

// MARK: - Errors

enum PrayerTimeServiceError: LocalizedError {
    case invalidURL
    case badServerResponse
    case apiError(code: Int, status: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to construct the Aladhan API URL."
        case .badServerResponse:
            return "The server returned an unexpected response."
        case .apiError(let code, let status):
            return "Aladhan API error \(code): \(status)"
        }
    }
}
