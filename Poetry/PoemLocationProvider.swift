import CoreLocation
import Foundation

final class PoemLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var cityName: String?
    @Published private(set) var inscriptionPlace: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var hasRequestedLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestCityIfNeeded() {
        guard cityName == nil else { return }

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
            let city = placemark?.locality
                ?? placemark?.subAdministrativeArea
                ?? placemark?.administrativeArea
            let place = Self.makeInscriptionPlace(from: placemark, city: city)

            DispatchQueue.main.async {
                self.cityName = city
                self.inscriptionPlace = place
                self.hasRequestedLocation = false
            }
        }
    }

    private static func makeInscriptionPlace(from placemark: CLPlacemark?, city: String?) -> String? {
        guard let city, !city.isEmpty else { return nil }

        let cityPrefix = city.hasSuffix("市") ? String(city.dropLast()) : city

        if let pointOfInterest = placemark?.areasOfInterest?.first, !pointOfInterest.isEmpty {
            return "\(cityPrefix)\(poeticSuffix(for: pointOfInterest))"
        }

        if let inlandWater = placemark?.inlandWater, !inlandWater.isEmpty {
            return "\(cityPrefix)\(poeticSuffix(for: inlandWater))"
        }

        if let ocean = placemark?.ocean, !ocean.isEmpty {
            return "\(cityPrefix)\(poeticSuffix(for: ocean))"
        }

        if let district = placemark?.subLocality, !district.isEmpty, !city.contains(district) {
            return "\(cityPrefix)\(district)"
        }

        return cityPrefix
    }

    private static func poeticSuffix(for place: String) -> String {
        guard !place.hasSuffix("畔"), !place.hasSuffix("邊"), !place.hasSuffix("边") else {
            return place
        }

        if place.contains("山")
            || place.contains("湖")
            || place.contains("海")
            || place.contains("江")
            || place.contains("河")
            || place.contains("溪")
            || place.contains("灣")
            || place.contains("湾") {
            return "\(place)畔"
        }

        return place
    }
}
