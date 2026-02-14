import Foundation

/// Aladhan API calculation method identifiers.
enum CalculationMethod: Int, CaseIterable, Codable, Identifiable {
    case mwl = 3
    case isna = 2
    case egypt = 5
    case makkah = 4
    case karachi = 1
    case tehran = 7
    case jafari = 0
    case gulf = 8
    case kuwait = 9
    case qatar = 10
    case singapore = 11
    case turkey = 13
    case dubai = 16

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .mwl:       return "Muslim World League"
        case .isna:      return "ISNA (North America)"
        case .egypt:     return "Egyptian General Authority"
        case .makkah:    return "Umm Al-Qura (Makkah)"
        case .karachi:   return "University of Islamic Sciences, Karachi"
        case .tehran:    return "Institute of Geophysics, Tehran"
        case .jafari:    return "Shia Ithna-Ashari (Jafari)"
        case .gulf:      return "Gulf Region"
        case .kuwait:    return "Kuwait"
        case .qatar:     return "Qatar"
        case .singapore: return "Singapore"
        case .turkey:    return "Diyanet (Turkey)"
        case .dubai:     return "Dubai"
        }
    }
}

/// Asr juristic school.
enum AsrSchool: Int, CaseIterable, Codable, Identifiable {
    case shafi = 0
    case hanafi = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .shafi:  return "Shafi'i / Maliki / Hanbali"
        case .hanafi: return "Hanafi"
        }
    }
}
