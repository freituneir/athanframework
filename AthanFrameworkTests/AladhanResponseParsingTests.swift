import Foundation
import Testing
@testable import AthanFramework

// MARK: - AladhanTimings.parseTime Tests

struct AladhanTimingsParseTimeTests {

    private let estTimezone = TimeZone(identifier: "America/New_York")!
    private let cairoTimezone = TimeZone(identifier: "Africa/Cairo")!

    /// Helper: returns a Date for a specific day at midnight in the given timezone.
    private func makeDate(year: Int, month: Int, day: Int, timezone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Parses plain HH:mm time string")
    func parsePlainTime() {
        let day = makeDate(year: 2026, month: 2, day: 13, timezone: estTimezone)
        let result = AladhanTimings.parseTime("05:23", on: day, timezone: estTimezone)

        #expect(result != nil)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = estTimezone
        #expect(calendar.component(.hour, from: result!) == 5)
        #expect(calendar.component(.minute, from: result!) == 23)
        #expect(calendar.component(.year, from: result!) == 2026)
        #expect(calendar.component(.month, from: result!) == 2)
        #expect(calendar.component(.day, from: result!) == 13)
    }

    @Test("Parses time string with timezone annotation like '05:23 (EET)'")
    func parseTimeWithTimezoneAnnotation() {
        let day = makeDate(year: 2026, month: 6, day: 15, timezone: cairoTimezone)
        let result = AladhanTimings.parseTime("05:23 (EET)", on: day, timezone: cairoTimezone)

        #expect(result != nil)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = cairoTimezone
        #expect(calendar.component(.hour, from: result!) == 5)
        #expect(calendar.component(.minute, from: result!) == 23)
    }

    @Test("Parses midnight time string 00:00")
    func parseMidnight() {
        let day = makeDate(year: 2026, month: 1, day: 1, timezone: estTimezone)
        let result = AladhanTimings.parseTime("00:00", on: day, timezone: estTimezone)

        #expect(result != nil)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = estTimezone
        #expect(calendar.component(.hour, from: result!) == 0)
        #expect(calendar.component(.minute, from: result!) == 0)
    }

    @Test("Parses end-of-day time string 23:59")
    func parseEndOfDay() {
        let day = makeDate(year: 2026, month: 12, day: 31, timezone: estTimezone)
        let result = AladhanTimings.parseTime("23:59", on: day, timezone: estTimezone)

        #expect(result != nil)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = estTimezone
        #expect(calendar.component(.hour, from: result!) == 23)
        #expect(calendar.component(.minute, from: result!) == 59)
    }

    @Test("Returns nil for empty string")
    func parseEmptyString() {
        let day = makeDate(year: 2026, month: 1, day: 1, timezone: estTimezone)
        let result = AladhanTimings.parseTime("", on: day, timezone: estTimezone)
        #expect(result == nil)
    }

    @Test("Returns nil for malformed string")
    func parseMalformedString() {
        let day = makeDate(year: 2026, month: 1, day: 1, timezone: estTimezone)

        #expect(AladhanTimings.parseTime("abc", on: day, timezone: estTimezone) == nil)
        #expect(AladhanTimings.parseTime("12", on: day, timezone: estTimezone) == nil)
        #expect(AladhanTimings.parseTime("12:ab", on: day, timezone: estTimezone) == nil)
    }

    @Test("Parsed time uses the correct timezone offset")
    func parseTimeTimezoneOffset() {
        // Parse the same wall-clock time in two different timezones.
        // The resulting absolute Date values should differ by the timezone offset.
        let day1 = makeDate(year: 2026, month: 3, day: 10, timezone: estTimezone)
        let day2 = makeDate(year: 2026, month: 3, day: 10, timezone: cairoTimezone)

        let estResult = AladhanTimings.parseTime("12:00", on: day1, timezone: estTimezone)!
        let cairoResult = AladhanTimings.parseTime("12:00", on: day2, timezone: cairoTimezone)!

        // EST is UTC-5, Cairo (EET) is UTC+2 => 7 hours difference
        let diff = estResult.timeIntervalSince(cairoResult)
        #expect(abs(diff - 7 * 3600) < 1)
    }
}

// MARK: - Full JSON Response Decoding Tests

struct AladhanCalendarResponseDecodingTests {

    /// Minimal valid JSON matching the Aladhan API schema for one day.
    private let singleDayJSON = """
    {
        "code": 200,
        "status": "OK",
        "data": [
            {
                "timings": {
                    "Fajr": "05:12 (EST)",
                    "Sunrise": "06:38 (EST)",
                    "Dhuhr": "12:15 (EST)",
                    "Asr": "15:20 (EST)",
                    "Sunset": "17:52 (EST)",
                    "Maghrib": "17:52 (EST)",
                    "Isha": "19:12 (EST)",
                    "Imsak": "05:02 (EST)",
                    "Midnight": "00:15 (EST)",
                    "Firstthird": "22:14 (EST)",
                    "Lastthird": "02:16 (EST)"
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
                    "method": {
                        "id": 2,
                        "name": "Islamic Society of North America (ISNA)"
                    }
                }
            }
        ]
    }
    """

    @Test("Decodes a valid single-day response")
    func decodeSingleDay() throws {
        let data = singleDayJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)

        #expect(response.code == 200)
        #expect(response.status == "OK")
        #expect(response.data.count == 1)

        let dayData = response.data[0]
        #expect(dayData.timings.Fajr == "05:12 (EST)")
        #expect(dayData.timings.Sunrise == "06:38 (EST)")
        #expect(dayData.timings.Dhuhr == "12:15 (EST)")
        #expect(dayData.timings.Asr == "15:20 (EST)")
        #expect(dayData.timings.Maghrib == "17:52 (EST)")
        #expect(dayData.timings.Isha == "19:12 (EST)")
        #expect(dayData.timings.Imsak == "05:02 (EST)")
        #expect(dayData.timings.Midnight == "00:15 (EST)")
    }

    @Test("Decodes gregorian date fields")
    func decodeGregorianDate() throws {
        let data = singleDayJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)

        let greg = response.data[0].date.gregorian
        #expect(greg.date == "13-02-2026")
        #expect(greg.format == "DD-MM-YYYY")
        #expect(greg.day == "13")
        #expect(greg.year == "2026")
        #expect(greg.weekday.en == "Friday")
        #expect(greg.month.number == 2)
        #expect(greg.month.en == "February")
    }

    @Test("Decodes hijri date fields")
    func decodeHijriDate() throws {
        let data = singleDayJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)

        let hijri = response.data[0].date.hijri
        #expect(hijri.date == "25-07-1447")
        #expect(hijri.day == "25")
        #expect(hijri.year == "1447")
        #expect(hijri.weekday.en == "Al Juma'a")
        #expect(hijri.weekday.ar == "الجمعة")
        #expect(hijri.month.number == 7)
        #expect(hijri.month.en == "Rajab")
        #expect(hijri.month.ar == "رجب")
    }

    @Test("Decodes meta fields")
    func decodeMeta() throws {
        let data = singleDayJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)

        let meta = response.data[0].meta
        #expect(meta.latitude == 40.7128)
        #expect(meta.longitude == -74.006)
        #expect(meta.timezone == "America/New_York")
        #expect(meta.method.id == 2)
        #expect(meta.method.name == "Islamic Society of North America (ISNA)")
    }

    @Test("Decodes optional Firstthird and Lastthird")
    func decodeOptionalFields() throws {
        let data = singleDayJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)

        #expect(response.data[0].timings.Firstthird == "22:14 (EST)")
        #expect(response.data[0].timings.Lastthird == "02:16 (EST)")
    }

    @Test("Decodes response where Firstthird/Lastthird are absent")
    func decodeWithMissingOptionalFields() throws {
        let json = """
        {
            "code": 200,
            "status": "OK",
            "data": [
                {
                    "timings": {
                        "Fajr": "05:12",
                        "Sunrise": "06:38",
                        "Dhuhr": "12:15",
                        "Asr": "15:20",
                        "Sunset": "17:52",
                        "Maghrib": "17:52",
                        "Isha": "19:12",
                        "Imsak": "05:02",
                        "Midnight": "00:15"
                    },
                    "date": {
                        "readable": "01 Jan 2026",
                        "timestamp": "1767225600",
                        "gregorian": {
                            "date": "01-01-2026",
                            "format": "DD-MM-YYYY",
                            "day": "01",
                            "weekday": { "en": "Thursday" },
                            "month": { "number": 1, "en": "January" },
                            "year": "2026"
                        },
                        "hijri": {
                            "date": "01-07-1447",
                            "format": "DD-MM-YYYY",
                            "day": "01",
                            "weekday": { "en": "Al Khamees" },
                            "month": { "number": 7, "en": "Rajab" },
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
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)

        #expect(response.data[0].timings.Firstthird == nil)
        #expect(response.data[0].timings.Lastthird == nil)
    }

    @Test("Decodes empty data array")
    func decodeEmptyDataArray() throws {
        let json = """
        {
            "code": 200,
            "status": "OK",
            "data": []
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)

        #expect(response.data.isEmpty)
    }

    @Test("Decodes multi-day response")
    func decodeMultipleDays() throws {
        let json = """
        {
            "code": 200,
            "status": "OK",
            "data": [
                {
                    "timings": {
                        "Fajr": "05:12", "Sunrise": "06:38", "Dhuhr": "12:15",
                        "Asr": "15:20", "Sunset": "17:52", "Maghrib": "17:52",
                        "Isha": "19:12", "Imsak": "05:02", "Midnight": "00:15"
                    },
                    "date": {
                        "readable": "01 Jan 2026", "timestamp": "1767225600",
                        "gregorian": {
                            "date": "01-01-2026", "format": "DD-MM-YYYY", "day": "01",
                            "weekday": { "en": "Thursday" },
                            "month": { "number": 1, "en": "January" }, "year": "2026"
                        },
                        "hijri": {
                            "date": "01-07-1447", "format": "DD-MM-YYYY", "day": "01",
                            "weekday": { "en": "Al Khamees" },
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
                        "Fajr": "05:11", "Sunrise": "06:37", "Dhuhr": "12:15",
                        "Asr": "15:21", "Sunset": "17:53", "Maghrib": "17:53",
                        "Isha": "19:13", "Imsak": "05:01", "Midnight": "00:15"
                    },
                    "date": {
                        "readable": "02 Jan 2026", "timestamp": "1767312000",
                        "gregorian": {
                            "date": "02-01-2026", "format": "DD-MM-YYYY", "day": "02",
                            "weekday": { "en": "Friday" },
                            "month": { "number": 1, "en": "January" }, "year": "2026"
                        },
                        "hijri": {
                            "date": "02-07-1447", "format": "DD-MM-YYYY", "day": "02",
                            "weekday": { "en": "Al Juma'a" },
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
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)

        #expect(response.data.count == 2)
        #expect(response.data[0].date.gregorian.day == "01")
        #expect(response.data[1].date.gregorian.day == "02")
        #expect(response.data[0].timings.Fajr == "05:12")
        #expect(response.data[1].timings.Fajr == "05:11")
    }

    @Test("Decoding fails for invalid JSON")
    func decodeInvalidJSON() {
        let json = "{ not valid json }"
        let data = json.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)
        }
    }

    @Test("Decoding fails when required timing field is missing")
    func decodeMissingRequiredTimingField() {
        // "Fajr" is missing from the timings
        let json = """
        {
            "code": 200,
            "status": "OK",
            "data": [
                {
                    "timings": {
                        "Sunrise": "06:38", "Dhuhr": "12:15",
                        "Asr": "15:20", "Sunset": "17:52", "Maghrib": "17:52",
                        "Isha": "19:12", "Imsak": "05:02", "Midnight": "00:15"
                    },
                    "date": {
                        "readable": "01 Jan 2026", "timestamp": "1767225600",
                        "gregorian": {
                            "date": "01-01-2026", "format": "DD-MM-YYYY", "day": "01",
                            "weekday": { "en": "Thursday" },
                            "month": { "number": 1, "en": "January" }, "year": "2026"
                        },
                        "hijri": {
                            "date": "01-07-1447", "format": "DD-MM-YYYY", "day": "01",
                            "weekday": { "en": "Al Khamees" },
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
        let data = json.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AladhanCalendarResponse.self, from: data)
        }
    }

    @Test("AladhanTimings round-trip encode/decode preserves values")
    func timingsRoundTrip() throws {
        let timings = AladhanTimings(
            Fajr: "05:12",
            Sunrise: "06:38",
            Dhuhr: "12:15",
            Asr: "15:20",
            Sunset: "17:52",
            Maghrib: "17:52",
            Isha: "19:12",
            Imsak: "05:02",
            Midnight: "00:15",
            Firstthird: nil,
            Lastthird: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(timings)
        let decoded = try JSONDecoder().decode(AladhanTimings.self, from: data)

        #expect(decoded.Fajr == timings.Fajr)
        #expect(decoded.Sunrise == timings.Sunrise)
        #expect(decoded.Dhuhr == timings.Dhuhr)
        #expect(decoded.Asr == timings.Asr)
        #expect(decoded.Maghrib == timings.Maghrib)
        #expect(decoded.Isha == timings.Isha)
        #expect(decoded.Firstthird == nil)
        #expect(decoded.Lastthird == nil)
    }
}

// MARK: - Model Enum Tests

struct CalculationMethodTests {

    @Test("All cases have unique raw values")
    func uniqueRawValues() {
        let rawValues = CalculationMethod.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("Raw values match Aladhan API method IDs")
    func rawValuesMatchAPIIds() {
        #expect(CalculationMethod.jafari.rawValue == 0)
        #expect(CalculationMethod.karachi.rawValue == 1)
        #expect(CalculationMethod.isna.rawValue == 2)
        #expect(CalculationMethod.mwl.rawValue == 3)
        #expect(CalculationMethod.makkah.rawValue == 4)
        #expect(CalculationMethod.egypt.rawValue == 5)
        #expect(CalculationMethod.tehran.rawValue == 7)
        #expect(CalculationMethod.gulf.rawValue == 8)
        #expect(CalculationMethod.kuwait.rawValue == 9)
        #expect(CalculationMethod.qatar.rawValue == 10)
        #expect(CalculationMethod.singapore.rawValue == 11)
        #expect(CalculationMethod.turkey.rawValue == 13)
        #expect(CalculationMethod.dubai.rawValue == 16)
    }

    @Test("All cases have non-empty display names")
    func displayNamesNotEmpty() {
        for method in CalculationMethod.allCases {
            #expect(!method.displayName.isEmpty)
        }
    }

    @Test("id matches rawValue for Identifiable conformance")
    func identifiableId() {
        for method in CalculationMethod.allCases {
            #expect(method.id == method.rawValue)
        }
    }
}

struct AsrSchoolTests {

    @Test("Shafi is 0, Hanafi is 1")
    func rawValues() {
        #expect(AsrSchool.shafi.rawValue == 0)
        #expect(AsrSchool.hanafi.rawValue == 1)
    }

    @Test("Display names are descriptive")
    func displayNames() {
        #expect(AsrSchool.shafi.displayName.contains("Shafi"))
        #expect(AsrSchool.hanafi.displayName.contains("Hanafi"))
    }
}

struct PrayerEnumTests {

    @Test("All 5 prayers are present")
    func allCases() {
        #expect(Prayer.allCases.count == 5)
    }

    @Test("Sort order is chronological")
    func sortOrder() {
        let sorted = Prayer.allCases.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted == [.fajr, .dhuhr, .asr, .maghrib, .isha])
    }

    @Test("Fajr has shorter snooze duration")
    func fajrSnooze() {
        #expect(Prayer.fajr.defaultSnoozeDuration == 120)
        #expect(Prayer.dhuhr.defaultSnoozeDuration == 300)
        #expect(Prayer.asr.defaultSnoozeDuration == 300)
        #expect(Prayer.maghrib.defaultSnoozeDuration == 300)
        #expect(Prayer.isha.defaultSnoozeDuration == 300)
    }

    @Test("aladhanKey matches API field names")
    func aladhanKeys() {
        #expect(Prayer.fajr.aladhanKey == "Fajr")
        #expect(Prayer.dhuhr.aladhanKey == "Dhuhr")
        #expect(Prayer.asr.aladhanKey == "Asr")
        #expect(Prayer.maghrib.aladhanKey == "Maghrib")
        #expect(Prayer.isha.aladhanKey == "Isha")
    }
}
