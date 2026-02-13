import CoreLocation
import Foundation

/// Errors specific to location operations.
enum LocationError: LocalizedError {
    case permissionDenied
    case permissionRestricted
    case locationUnknown
    case requestAlreadyInProgress
    case geocodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission was denied. Please enable it in Settings."
        case .permissionRestricted:
            return "Location access is restricted on this device."
        case .locationUnknown:
            return "Unable to determine your location."
        case .requestAlreadyInProgress:
            return "A location request is already in progress."
        case .geocodingFailed:
            return "Unable to determine the name of your location."
        }
    }
}

/// Wraps `CLLocationManager` as an `@Observable` service for the app.
///
/// Provides one-shot location via async/await, significant-change monitoring
/// for background updates, and reverse geocoding for display names.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    // MARK: - Published State

    private(set) var currentLocation: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var locationName: String = ""

    // MARK: - Significant Location Change Stream

    /// An `AsyncStream` that emits every time a significant location change is detected.
    /// The `AppCoordinator` can iterate over this to trigger prayer-time refreshes.
    let significantLocationChanges: AsyncStream<CLLocation>
    private let significantLocationContinuation: AsyncStream<CLLocation>.Continuation

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    /// Continuation for the one-shot `getCurrentLocation()` call.
    /// Only one request may be in flight at a time.
    private var oneShotContinuation: CheckedContinuation<CLLocation, any Error>?

    private var isMonitoringSignificantChanges = false

    // MARK: - Init

    override init() {
        let (stream, continuation) = AsyncStream<CLLocation>.makeStream()
        self.significantLocationChanges = stream
        self.significantLocationContinuation = continuation
        self.authorizationStatus = locationManager.authorizationStatus

        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    deinit {
        significantLocationContinuation.finish()
    }

    // MARK: - Public API

    /// Requests when-in-use authorization. Safe to call multiple times;
    /// has no effect if authorization has already been determined.
    func requestPermission() {
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    /// Returns the device's current location as a one-shot async call.
    ///
    /// Throws `LocationError` if permissions are denied/restricted or if
    /// the location cannot be determined.
    func getCurrentLocation() async throws -> CLLocation {
        guard oneShotContinuation == nil else {
            throw LocationError.requestAlreadyInProgress
        }

        switch authorizationStatus {
        case .denied:
            throw LocationError.permissionDenied
        case .restricted:
            throw LocationError.permissionRestricted
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Poll for authorization change (up to 30 seconds for the user to respond).
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(500))
                if authorizationStatus != .notDetermined {
                    break
                }
            }
            // Re-check after waiting.
            switch authorizationStatus {
            case .denied:
                throw LocationError.permissionDenied
            case .restricted:
                throw LocationError.permissionRestricted
            case .notDetermined:
                // User never responded or dismissed the dialog.
                throw LocationError.permissionDenied
            default:
                break
            }
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.oneShotContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    /// Begins monitoring for significant location changes (cell-tower level).
    /// Ideal for background updates — wakes the app when the user moves ~500m+.
    func startMonitoringSignificantChanges() {
        guard !isMonitoringSignificantChanges else { return }
        isMonitoringSignificantChanges = true
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startMonitoringSignificantLocationChanges()
    }

    /// Stops significant-change monitoring.
    func stopMonitoring() {
        guard isMonitoringSignificantChanges else { return }
        isMonitoringSignificantChanges = false
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        currentLocation = location

        // If a one-shot request is pending, fulfill it and stop.
        if let continuation = oneShotContinuation {
            oneShotContinuation = nil
            continuation.resume(returning: location)
        }

        // If monitoring significant changes, push to the stream.
        if isMonitoringSignificantChanges {
            significantLocationContinuation.yield(location)
        }

        reverseGeocode(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        if let continuation = oneShotContinuation {
            oneShotContinuation = nil
            if let clError = error as? CLError, clError.code == .denied {
                continuation.resume(throwing: LocationError.permissionDenied)
            } else {
                continuation.resume(throwing: LocationError.locationUnknown)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Reverse Geocoding

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let placemark = placemarks?.first else { return }
            let city = placemark.locality ?? placemark.administrativeArea ?? ""
            let country = placemark.country ?? ""
            if city.isEmpty {
                self.locationName = country
            } else if country.isEmpty {
                self.locationName = city
            } else {
                self.locationName = "\(city), \(country)"
            }
        }
    }
}
