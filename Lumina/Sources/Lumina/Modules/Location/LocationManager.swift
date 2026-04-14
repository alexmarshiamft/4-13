// LocationManager.swift – CoreLocation geofencing and Wi-Fi SSID triggers
// Lumina: AI-powered reminders, task management, and focus app
//
// Module E: Location & Environment Triggers
//  - Geofenced task triggers (arrive/leave region)
//  - Wi-Fi SSID connection detection
//  - Privacy-first: all processing on device

import Foundation
import CoreLocation
#if canImport(SystemConfiguration)
import SystemConfiguration.CaptiveNetwork
#endif
#if canImport(NetworkExtension)
import NetworkExtension
#endif

// MARK: - Trigger Direction
enum GeofenceTrigger: String, Codable {
    case onArrive = "on_arrive"
    case onLeave  = "on_leave"
    case both     = "both"
}

// MARK: - LocationManager
@MainActor
final class LocationManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isMonitoringRegions = false
    @Published var monitoredRegionCount = 0

    // MARK: - Private
    private let locationManager = CLLocationManager()
    private var onLocationUpdate: ((CLLocation) -> Void)?
    private var regionTriggerHandlers: [String: (GeofenceTrigger) -> Void] = [:]

    // MARK: - Init
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50  // meters
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Authorization
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Start / Stop Updating
    func startUpdatingLocation() {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - Geofencing (Regions)
    /// Register a geofenced trigger for a task.
    func addGeofence(
        taskID: UUID,
        identifier: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        trigger: GeofenceTrigger,
        handler: @escaping (GeofenceTrigger) -> Void
    ) {
        guard authorizationStatus == .authorizedAlways else {
            requestAlwaysAuthorization()
            return
        }

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: center,
            radius: min(radiusMeters, locationManager.maximumRegionMonitoringDistance),
            identifier: identifier
        )
        region.notifyOnEntry = (trigger == .onArrive || trigger == .both)
        region.notifyOnExit  = (trigger == .onLeave  || trigger == .both)

        regionTriggerHandlers[identifier] = handler
        locationManager.startMonitoring(for: region)
        monitoredRegionCount = locationManager.monitoredRegions.count
        isMonitoringRegions = !locationManager.monitoredRegions.isEmpty
    }

    /// Remove geofence monitoring for a specific task.
    func removeGeofence(identifier: String) {
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager.stopMonitoring(for: region)
            regionTriggerHandlers.removeValue(forKey: identifier)
        }
        monitoredRegionCount = locationManager.monitoredRegions.count
        isMonitoringRegions = !locationManager.monitoredRegions.isEmpty
    }

    func removeAllGeofences() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        regionTriggerHandlers.removeAll()
        monitoredRegionCount = 0
        isMonitoringRegions = false
    }

    // MARK: - Wi-Fi SSID Detection
    /// Returns the current Wi-Fi SSID if accessible, otherwise nil.
    /// Note: Requires "Access Wi-Fi Information" entitlement.
    func currentWiFiSSID() async -> String? {
#if canImport(NetworkExtension)
        // iOS 14+ / macOS 11+ – preferred API
        do {
            let interfaces = try await NEHotspotNetwork.fetchCurrent()
            return interfaces?.ssid
        } catch {
            return nil
        }
#elseif canImport(SystemConfiguration)
        // Legacy macOS path
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for interface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String {
                return ssid
            }
        }
        return nil
#else
        return nil
#endif
    }

    /// Registers a handler to fire when connecting to a named Wi-Fi SSID.
    /// Uses a polling approach (every 30s) since there's no push notification for SSID changes.
    func monitorWiFiSSID(_ targetSSID: String, handler: @escaping () -> Void) {
        Task {
            var previousSSID: String? = await currentWiFiSSID()
            while true {
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30 seconds
                let currentSSID = await currentWiFiSSID()
                if currentSSID == targetSSID && previousSSID != targetSSID {
                    await MainActor.run { handler() }
                }
                previousSSID = currentSSID
            }
        }
    }

    // MARK: - Convenience: Register geofence from LuminaTask
    func registerTrigger(for task: LuminaTask, notificationScheduler: NotificationScheduler) {
        guard task.triggerType == .location,
              let lat = task.latitude,
              let lon = task.longitude else { return }

        let radius = task.triggerRadiusMeters ?? 100.0

        addGeofence(
            taskID: task.id,
            identifier: "geofence-\(task.id.uuidString)",
            latitude: lat,
            longitude: lon,
            radiusMeters: radius,
            trigger: .onArrive
        ) { [weak notificationScheduler] direction in
            Task { @MainActor in
                await notificationScheduler?.schedule(task: task)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.onLocationUpdate?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didEnterRegion region: CLRegion) {
        Task { @MainActor in
            self.regionTriggerHandlers[region.identifier]?(.onArrive)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didExitRegion region: CLRegion) {
        Task { @MainActor in
            self.regionTriggerHandlers[region.identifier]?(.onLeave)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     monitoringDidFailFor region: CLRegion?,
                                     withError error: Error) {
        print("[Lumina] Region monitoring failed: \(error.localizedDescription)")
    }
}
