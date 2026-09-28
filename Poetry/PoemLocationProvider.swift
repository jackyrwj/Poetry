import CoreLocation
import Foundation

/// Whether new inscriptions and share images may carry a place name.
enum PoemLocationPreference {
    static let storageKey = "showsInscriptionPlace"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }

    /// Drops a stored place when the reader has turned place names off.
    static func visible(_ place: String?) -> String? {
        isEnabled ? place : nil
    }
}

final class PoemLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private var resolvedCityName: String?
    @Published private var resolvedInscriptionPlace: String?

    var cityName: String? { PoemLocationPreference.visible(resolvedCityName) }
    var inscriptionPlace: String? { PoemLocationPreference.visible(resolvedInscriptionPlace) }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var hasRequestedLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestCityIfNeeded() {
        guard PoemLocationPreference.isEnabled, resolvedCityName == nil else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestSingleLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestSingleLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        reverseGeocode(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        hasRequestedLocation = false
    }

    private func requestSingleLocation() {
        guard !hasRequestedLocation else { return }
        hasRequestedLocation = true
        manager.requestLocation()
    }

    private func reverseGeocode(_ location: CLLocation) {
        guard !geocoder.isGeocoding else { return }

        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_Hans_CN")) { [weak self] placemarks, _ in
            guard let self else { return }
            let placemark = placemarks?.first
            let city = [placemark?.locality, placemark?.subAdministrativeArea, placemark?.administrativeArea]
                .compactMap { $0.flatMap(Self.cleanedName) }
                .first
            let place = Self.makeInscriptionPlace(city: city)

            DispatchQueue.main.async {
                self.resolvedCityName = city
                self.resolvedInscriptionPlace = place
                self.hasRequestedLocation = false
            }
        }
    }

    /// Only the city goes into a colophon ("於深圳"). Nearby landmarks and
    /// districts vary with a few hundred metres of drift and would reveal more
    /// than the privacy policy promises.
    private static func makeInscriptionPlace(city: String?) -> String? {
        guard let city, !city.isEmpty else { return nil }
        return city.hasSuffix("市") ? String(city.dropLast()) : city
    }

    /// Map names can carry qualifiers ("深圳市(南山)") or come back in Latin
    /// script abroad ("Springfield"). A colophon only takes a Chinese name, so
    /// strip qualifiers and reject anything else.
    private static func cleanedName(_ raw: String) -> String? {
        var name = raw
        for (open, close) in [("(", ")"), ("（", "）"), ("[", "]"), ("【", "】")] {
            while let start = name.range(of: open),
                  let end = name.range(of: close, range: start.upperBound..<name.endIndex) {
                name.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.allSatisfy(isHan) else { return nil }
        return name
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF:
            return true
        default:
            return false
        }
    }
}
