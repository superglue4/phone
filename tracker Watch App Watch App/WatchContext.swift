//
//  WatchContext.swift
//  tracker Watch App
//
//  iPhone으로부터 GPX 경로 수신 + Watch 현재 위치 관리.
//

import Foundation
import Combine
import CoreLocation
import WatchConnectivity

@MainActor
final class WatchContext: NSObject, ObservableObject {
    @Published var routeName: String = ""
    @Published var routeSegments: [[CLLocationCoordinate2D]] = []
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var statusMessage: String = "iPhone에서 GPX를 선택하세요"
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        configureConnectivity()
        configureLocation()
    }

    private func configureConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        applyContext(session.receivedApplicationContext)
    }

    private func configureLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    fileprivate func applyContext(_ context: [String: Any]) {
        guard let rawSegments = context["segments"] as? [[[Double]]] else { return }
        let name = context["name"] as? String ?? ""

        let segments: [[CLLocationCoordinate2D]] = rawSegments.map { segment in
            segment.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count == 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            }
        }.filter { !$0.isEmpty }

        self.routeName = name
        self.routeSegments = segments
        if segments.isEmpty {
            self.statusMessage = "수신된 경로 없음"
        } else {
            let totalPoints = segments.reduce(0) { $0 + $1.count }
            self.statusMessage = "\(segments.count)개 경로 · \(totalPoints)개 좌표"
        }
    }
}

extension WatchContext: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        Task { @MainActor in
            if ctx.isEmpty {
                self.statusMessage = "iPhone에서 GPX를 선택하세요"
            } else {
                self.applyContext(ctx)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            self.applyContext(applicationContext)
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
#endif
}

extension WatchContext: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.userCoordinate = coord
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusMessage = "위치 오류: \(error.localizedDescription)"
        }
    }
}
