//
//  ContentView.swift
//  tracker Watch App
//

import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @StateObject private var ctx = WatchContext()
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        TabView {
            mapTab
                .tabItem { Label("지도", systemImage: "map") }

            infoTab
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .onChange(of: ctx.routeSegments.count) { _, _ in
            focusOnRoute()
        }
        .onAppear {
            focusOnRoute()
        }
    }

    private var mapTab: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            ForEach(Array(ctx.routeSegments.enumerated()), id: \.offset) { _, segment in
                if segment.count >= 2 {
                    MapPolyline(coordinates: segment)
                        .stroke(.blue, lineWidth: 3)
                }
            }

            if let start = firstTrackCoordinate {
                Marker("Start", coordinate: start)
                    .tint(.green)
            }
            if let end = lastTrackCoordinate, end.latitude != firstTrackCoordinate?.latitude {
                Marker("End", coordinate: end)
                    .tint(.red)
            }
        }
        .mapControls {
            MapCompass()
        }
    }

    private var infoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(ctx.routeName.isEmpty ? "선택된 경로 없음" : ctx.routeName)
                    .font(.headline)

                Text(ctx.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                if let coord = ctx.userCoordinate {
                    Text("현재 위치")
                        .font(.caption.weight(.semibold))
                    Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(locationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button("경로로 이동") {
                    focusOnRoute()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ctx.routeSegments.isEmpty)

                Button("내 위치로 이동") {
                    focusOnUser()
                }
                .buttonStyle(.bordered)
                .disabled(ctx.userCoordinate == nil)
            }
            .padding(.horizontal)
        }
    }

    private var firstTrackCoordinate: CLLocationCoordinate2D? {
        ctx.routeSegments.first(where: { $0.count >= 2 })?.first
    }

    private var lastTrackCoordinate: CLLocationCoordinate2D? {
        ctx.routeSegments.last(where: { $0.count >= 2 })?.last
    }

    private var locationStatusText: String {
        switch ctx.authorizationStatus {
        case .notDetermined: return "위치 권한 요청 중..."
        case .denied, .restricted: return "위치 권한이 거부됨"
        case .authorizedAlways, .authorizedWhenInUse: return "GPS 신호 대기 중"
        @unknown default: return "위치 상태 알 수 없음"
        }
    }

    private func focusOnRoute() {
        let tracks = ctx.routeSegments.filter { $0.count >= 2 }.flatMap { $0 }
        guard !tracks.isEmpty else { return }
        let rect = mapRect(for: tracks)
        cameraPosition = .rect(rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.15))
    }

    private func focusOnUser() {
        guard let coord = ctx.userCoordinate else { return }
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
    }

    private func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let points = coordinates.map(MKMapPoint.init)
        guard var rect = points.first.map({ MKMapRect(origin: $0, size: MKMapSize(width: 0, height: 0)) }) else {
            return .world
        }
        for point in points.dropFirst() {
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        return rect
    }
}

#Preview {
    ContentView()
}
