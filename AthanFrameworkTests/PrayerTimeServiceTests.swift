import Foundation
import SwiftData
import Testing
@testable import AthanFramework

// MARK: - Mock URLProtocol

/// A URLProtocol subclass that intercepts network requests and returns
/// canned responses, allowing PrayerTimeService to be tested without a network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var responseStatusCode: Int = 200
    nonisolated(unsafe) static var responseError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = MockURLProtocol.responseError {
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        if let data = MockURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        responseData = nil
        responseStatusCode = 200
        responseError = nil
    }
}

// MARK: - Test Fixtures

/// Generates valid Aladhan API JSON responses for testing.
enum AladhanFixtures {

    /// A valid single-day response for Feb 13, 2026 in New York.
    static let singleDayJSON = """
    {
        "code": 200,
        "status": "OK",
        "data": [
            {
                "timings": {
                    "Fajr": "05:47",
                    "Sunrise": "06:55",
                    "Dhuhr": "12:10",
                    "Asr": "15:06",
                    "Sunset": "17:25",
                    "Maghrib": "17:25",
                    "Isha": "18:41",
                    "Imsak": "05:37",
                    "Midnight": "00:10"
                },
                "date": {
                    "readable": "13 Feb 2026",
                    "timestamp": "1771027200",
                    "gregorian": {
                        "date": "13-02-2026",
                        "format": "DD-MM-YYYY",
                        "day": "13",
                        "weekday": { "en": "Friday" },
                        "month": { "number": 2, "en": "February" },
                        "year": "2026"
                    },
                    "hijri": {
                        "date": "25-07-1447",
                        "format": "DD-MM-YYYY",
                        "day": "25",
                        "weekday": { "en": "Al Juma'a", "ar": "الجمعة" },
                        "month": { "number": 7, "en": "Rajab", "ar": "رجب" },
                        "year": "1447"
                    }
                },
                "meta": {
                    "latitude": 40.7128,
                    "longitude": -74.006,
                    "timezone": "America/New_York",
                    "method": { "id": 2, "name": "ISNA" }
                }
            }
        ]
    }
    """

    /// A two-day response for a minimal multi-day fetch test.
    static let twoDayJSON = """
    {
        "code": 200,
        "status": "OK",
        "data": [
            {
                "timings": {
                    "Fajr": "05:47", "Sunrise": "06:55", "Dhuhr": "12:10",
                    "Asr": "15:06", "Sunset": "17:25", "Maghrib": "17:25",
                    "Isha": "18:41", "Imsak": "05:37", "Midnight": "00:10"
                },
                "date": {
                    "readable": "01 Feb 2026", "timestamp": "1769990400",
                    "gregorian": {
                        "date": "01-02-2026", "format": "DD-MM-YYYY", "day": "01",
                        "weekday": { "en": "Sunday" },
                        "month": { "number": 2, "en": "February" }, "year": "2026"
                    },
                    "hijri": {
                        "date": "13-07-1447", "format": "DD-MM-YYYY", "day": "13",
                        "weekday": { "en": "Al Ahad" },
                        "month": { "number": 7, "en": "Rajab" }, "year": "1447"
                    }
                },
                "meta": {
                    "latitude": 40.7128, "longitude": -74.006,
                    "timezone": "America/New_York",
                    "method": { "id": 2, "name": "ISNA" }
                }
            },
            {
                "timings": {
                    "Fajr": "05:46", "Sunrise": "06:54", "Dhuhr": "12:10",
                    "Asr": "15:07", "Sunset": "17:26", "Maghrib": "17:26",
                    "Isha": "18:42", "Imsak": "05:36", "Midnight": "00:10"
                },
                "date": {
                    "readable": "02 Feb 2026", "timestamp": "1770076800",
                    "gregorian": {
                        "date": "02-02-2026", "format": "DD-MM-YYYY", "day": "02",
                        "weekday": { "en": "Monday" },
                        "month": { "number": 2, "en": "February" }, "year": "2026"
                    },
                    "hijri": {
                        "date": "14-07-1447", "format": "DD-MM-YYYY", "day": "14",
                        "weekday": { "en": "Al Ithnayn" },
                        "month": { "number": 7, "en": "Rajab" }, "year": "1447"
                    }
                },
                "meta": {
                    "latitude": 40.7128, "longitude": -74.006,
                    "timezone": "America/New_York",
                    "method": { "id": 2, "name": "ISNA" }
                }
            }
        ]
    }
    """

    /// An API-level error response (code != 200).
    static let apiErrorJSON = """
    {
        "code": 400,
        "status": "Bad Request - Invalid parameters",
        "data": []
    }
    """
}

// MARK: - Helper

/// Creates an in-memory SwiftData ModelContainer and returns its main context.
func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([DailyPrayerTimes.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

/// Creates a URLSession configured to use MockURLProtocol.
func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - PrayerTimeService Tests

@MainActor
struct PrayerTimeServiceFetchTests {

    @Test("fetchMonth returns parsed prayer times for each day in the response")
    func fetchMonthReturnsParsedTimes() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.twoDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        let results = try await service.fetchMonth(
            year: 2026,
            month: 2,
            latitude: 40.7128,
            longitude: -74.006,
            method: .isna,
            school: .shafi,
            timezone: "America/New_York"
        )

        #expect(results.count == 2)
    }

    @Test("fetchMonth populates all prayer time fields")
    func fetchMonthPopulatesPrayerFields() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.singleDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        let results = try await service.fetchMonth(
            year: 2026,
            month: 2,
            latitude: 40.7128,
            longitude: -74.006,
            method: .isna,
            school: .shafi,
            timezone: "America/New_York"
        )

        let entry = try #require(results.first)

        #expect(entry.fajr != nil)
        #expect(entry.sunrise != nil)
        #expect(entry.dhuhr != nil)
        #expect(entry.asr != nil)
        #expect(entry.maghrib != nil)
        #expect(entry.isha != nil)

        // Verify parsed hour values in the correct timezone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        #expect(calendar.component(.hour, from: entry.fajr!) == 5)
        #expect(calendar.component(.minute, from: entry.fajr!) == 47)
        #expect(calendar.component(.hour, from: entry.dhuhr!) == 12)
        #expect(calendar.component(.minute, from: entry.dhuhr!) == 10)
        #expect(calendar.component(.hour, from: entry.asr!) == 15)
        #expect(calendar.component(.hour, from: entry.maghrib!) == 17)
        #expect(calendar.component(.hour, from: entry.isha!) == 18)
    }

    @Test("fetchMonth populates metadata fields on DailyPrayerTimes")
    func fetchMonthPopulatesMetadata() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.singleDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        let results = try await service.fetchMonth(
            year: 2026,
            month: 2,
            latitude: 40.7128,
            longitude: -74.006,
            method: .isna,
            school: .shafi,
            timezone: "America/New_York"
        )

        let entry = try #require(results.first)

        #expect(entry.latitude == 40.7128)
        #expect(entry.longitude == -74.006)
        #expect(entry.timezone == "America/New_York")
        #expect(entry.calculationMethod == CalculationMethod.isna.rawValue)
        #expect(entry.gregorianDate == "13-02-2026")
        #expect(entry.hijriDate == "25-07-1447")
    }

    @Test("fetchMonth persists entries to SwiftData")
    func fetchMonthPersistsToSwiftData() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.twoDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        _ = try await service.fetchMonth(
            year: 2026,
            month: 2,
            latitude: 40.7128,
            longitude: -74.006,
            method: .isna,
            school: .shafi,
            timezone: "America/New_York"
        )

        // Query SwiftData directly to confirm persistence
        let descriptor = FetchDescriptor<DailyPrayerTimes>()
        let stored = try context.fetch(descriptor)
        #expect(stored.count == 2)
    }

    @Test("fetchMonth replaces existing entries for the same month")
    func fetchMonthReplacesExistingEntries() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.twoDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        // Fetch twice — should not duplicate
        _ = try await service.fetchMonth(
            year: 2026, month: 2,
            latitude: 40.7128, longitude: -74.006,
            method: .isna, school: .shafi,
            timezone: "America/New_York"
        )
        _ = try await service.fetchMonth(
            year: 2026, month: 2,
            latitude: 40.7128, longitude: -74.006,
            method: .isna, school: .shafi,
            timezone: "America/New_York"
        )

        let descriptor = FetchDescriptor<DailyPrayerTimes>()
        let stored = try context.fetch(descriptor)
        #expect(stored.count == 2)
    }

    @Test("fetchMonth sets isLoading to false after completion")
    func fetchMonthResetsLoadingState() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.singleDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        _ = try await service.fetchMonth(
            year: 2026, month: 2,
            latitude: 40.7128, longitude: -74.006,
            method: .isna, school: .shafi,
            timezone: "America/New_York"
        )

        #expect(service.isLoading == false)
        #expect(service.lastError == nil)
    }
}

@MainActor
struct PrayerTimeServiceErrorTests {

    @Test("fetchMonth throws on HTTP error status code")
    func fetchMonthThrowsOnHTTPError() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseStatusCode = 500
        MockURLProtocol.responseData = Data()

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        await #expect(throws: PrayerTimeServiceError.self) {
            _ = try await service.fetchMonth(
                year: 2026, month: 2,
                latitude: 40.7128, longitude: -74.006,
                method: .isna, school: .shafi,
                timezone: "America/New_York"
            )
        }

        #expect(service.isLoading == false)
        #expect(service.lastError != nil)
    }

    @Test("fetchMonth throws on API-level error (code != 200)")
    func fetchMonthThrowsOnAPIError() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.apiErrorJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        await #expect(throws: PrayerTimeServiceError.self) {
            _ = try await service.fetchMonth(
                year: 2026, month: 2,
                latitude: 40.7128, longitude: -74.006,
                method: .isna, school: .shafi,
                timezone: "America/New_York"
            )
        }

        #expect(service.lastError != nil)
    }

    @Test("fetchMonth throws on network error")
    func fetchMonthThrowsOnNetworkError() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseError = URLError(.notConnectedToInternet)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        await #expect(throws: (any Error).self) {
            _ = try await service.fetchMonth(
                year: 2026, month: 2,
                latitude: 40.7128, longitude: -74.006,
                method: .isna, school: .shafi,
                timezone: "America/New_York"
            )
        }

        #expect(service.isLoading == false)
        #expect(service.lastError != nil)
    }

    @Test("fetchMonth throws on invalid JSON")
    func fetchMonthThrowsOnInvalidJSON() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = "not json".data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        await #expect(throws: (any Error).self) {
            _ = try await service.fetchMonth(
                year: 2026, month: 2,
                latitude: 40.7128, longitude: -74.006,
                method: .isna, school: .shafi,
                timezone: "America/New_York"
            )
        }
    }
}

@MainActor
struct PrayerTimeServiceCacheTests {

    @Test("getCachedTimes returns nil when no data is cached")
    func getCachedTimesReturnsNilWhenEmpty() throws {
        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        let result = service.getCachedTimes(for: Date())
        #expect(result == nil)
    }

    @Test("getCachedTimes returns cached entry after fetch")
    func getCachedTimesReturnsCachedEntry() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.singleDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        _ = try await service.fetchMonth(
            year: 2026, month: 2,
            latitude: 40.7128, longitude: -74.006,
            method: .isna, school: .shafi,
            timezone: "America/New_York"
        )

        // Build the same date that would have been parsed from "13-02-2026"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let feb13 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 13))!

        let cached = service.getCachedTimes(for: feb13)
        #expect(cached != nil)
        #expect(cached?.gregorianDate == "13-02-2026")
    }

    @Test("getCachedTimes returns nil for a date that is not cached")
    func getCachedTimesReturnsNilForDifferentDate() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.singleDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        _ = try await service.fetchMonth(
            year: 2026, month: 2,
            latitude: 40.7128, longitude: -74.006,
            method: .isna, school: .shafi,
            timezone: "America/New_York"
        )

        // Query for March 1 which is not in the response
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let march1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

        let cached = service.getCachedTimes(for: march1)
        #expect(cached == nil)
    }
}

@MainActor
struct PrayerTimeServiceCalculationMethodTests {

    @Test("All CalculationMethod cases can be used in a fetch request")
    func allMethodsProduceValidURLs() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.singleDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        for method in CalculationMethod.allCases {
            // If this throws PrayerTimeServiceError.invalidURL, the URL building failed.
            // We allow other errors (mock returns same data for all methods, which is fine).
            let results = try await service.fetchMonth(
                year: 2026, month: 2,
                latitude: 40.7128, longitude: -74.006,
                method: method, school: .shafi,
                timezone: "America/New_York"
            )
            #expect(!results.isEmpty, "Method \(method.displayName) should return results")
        }
    }

    @Test("Both AsrSchool cases can be used in a fetch request")
    func bothSchoolsProduceValidURLs() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = AladhanFixtures.singleDayJSON.data(using: .utf8)

        let context = try makeInMemoryContext()
        let service = PrayerTimeService(modelContext: context, session: makeMockSession())

        for school in AsrSchool.allCases {
            let results = try await service.fetchMonth(
                year: 2026, month: 2,
                latitude: 40.7128, longitude: -74.006,
                method: .isna, school: school,
                timezone: "America/New_York"
            )
            #expect(!results.isEmpty, "School \(school.displayName) should return results")
        }
    }
}

// MARK: - PrayerTimeServiceError Tests

struct PrayerTimeServiceErrorDescriptionTests {

    @Test("invalidURL has a description")
    func invalidURLDescription() {
        let error = PrayerTimeServiceError.invalidURL
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("badServerResponse has a description")
    func badServerResponseDescription() {
        let error = PrayerTimeServiceError.badServerResponse
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("apiError includes code and status in description")
    func apiErrorDescription() {
        let error = PrayerTimeServiceError.apiError(code: 400, status: "Bad Request")
        let desc = error.errorDescription!
        #expect(desc.contains("400"))
        #expect(desc.contains("Bad Request"))
    }
}

// MARK: - DailyPrayerTimes Model Tests

struct DailyPrayerTimesModelTests {

    @Test("time(for:) returns correct field for each prayer")
    func timeForPrayer() {
        let entry = DailyPrayerTimes()
        let now = Date()
        let later = now.addingTimeInterval(3600)

        entry.fajr = now
        entry.dhuhr = now.addingTimeInterval(3600 * 6)
        entry.asr = now.addingTimeInterval(3600 * 9)
        entry.maghrib = now.addingTimeInterval(3600 * 12)
        entry.isha = later

        #expect(entry.time(for: .fajr) == now)
        #expect(entry.time(for: .isha) == later)
        #expect(entry.time(for: .dhuhr) != nil)
        #expect(entry.time(for: .asr) != nil)
        #expect(entry.time(for: .maghrib) != nil)
    }

    @Test("time(for:) returns nil when prayer time is not set")
    func timeForPrayerReturnsNilWhenNotSet() {
        let entry = DailyPrayerTimes()

        for prayer in Prayer.allCases {
            #expect(entry.time(for: prayer) == nil)
        }
    }

    @Test("Default values are set correctly")
    func defaultValues() {
        let entry = DailyPrayerTimes()

        #expect(entry.latitude == 0.0)
        #expect(entry.longitude == 0.0)
        #expect(entry.timezone == "")
        #expect(entry.calculationMethod == 2) // ISNA default
        #expect(entry.hijriDate == "")
        #expect(entry.gregorianDate == "")
    }
}
