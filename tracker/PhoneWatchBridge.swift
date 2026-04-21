//
//  PhoneWatchBridge.swift
//  tracker
//
//  iPhone 측 WatchConnectivity: 선택된 GPX 경로를 Apple Watch로 전송.
//

import Foundation
import Combine
import CoreLocation
import WatchConnectivity

@MainActor
final class PhoneWatchBridge: NSObject, ObservableObject {
    static let shared = PhoneWatchBridge()

    @Published private(set) var isReachable: Bool = false
    @Published private(set) var isPaired: Bool = false
    @Published private(set) var lastSendStatus: String = ""

    private override init() {
        super.init()
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastSendStatus = "이 기기는 WatchConnectivity 미지원"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendRoute(name: String, segments: [[CLLocationCoordinate2D]]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            lastSendStatus = "WCSession 활성화 대기 중"
            return
        }
        guard session.isPaired else {
            lastSendStatus = "페어링된 Apple Watch 없음"
            return
        }

        let encoded = Self.encode(name: name, segments: segments)

        do {
            try session.updateApplicationContext(encoded)
            lastSendStatus = "Watch 전송: \(segments.count)개 세그먼트"
        } catch {
            lastSendStatus = "전송 실패: \(error.localizedDescription)"
        }
    }

    static func encode(name: String, segments: [[CLLocationCoordinate2D]]) -> [String: Any] {
        let simplified = segments.map { segment -> [[Double]] in
            let reduced = downsample(segment, maxPoints: 500)
            return reduced.map { [$0.latitude, $0.longitude] }
        }
        return [
            "name": name,
            "segments": simplified,
            "ts": Date().timeIntervalSince1970
        ]
    }

    private static func downsample(
        _ points: [CLLocationCoordinate2D],
        maxPoints: Int
    ) -> [CLLocationCoordinate2D] {
        guard points.count > maxPoints, maxPoints > 1 else {
            return points
        }
        let stride = Double(points.count - 1) / Double(maxPoints - 1)
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let idx = Int((Double(i) * stride).rounded())
            result.append(points[min(idx, points.count - 1)])
        }
        return result
    }
}

extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.isPaired = session.isPaired
            if let error {
                self.lastSendStatus = "활성화 오류: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        Task { @MainActor in
            self.isPaired = paired
        }
    }
}
