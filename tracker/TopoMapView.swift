//
//  TopoMapView.swift
//  tracker
//
//  OpenTopoMap 타일을 사용하고 디스크 캐싱하는 MKMapView 래퍼.
//

import SwiftUI
import MapKit

struct TopoMapView: UIViewRepresentable {
    var segments: [[CLLocationCoordinate2D]]
    var userCoordinate: CLLocationCoordinate2D?
    var cameraTarget: CameraTarget?
    var onRegionChange: (MKCoordinateRegion) -> Void = { _ in }
    var onUserInteraction: () -> Void = {}

    struct CameraTarget: Equatable {
        let id: UUID
        let kind: Kind

        enum Kind {
            case region(MKCoordinateRegion)
            case mapRect(MKMapRect)
        }

        static func region(_ region: MKCoordinateRegion) -> CameraTarget {
            CameraTarget(id: UUID(), kind: .region(region))
        }

        static func mapRect(_ rect: MKMapRect) -> CameraTarget {
            CameraTarget(id: UUID(), kind: .mapRect(rect))
        }

        static func == (lhs: CameraTarget, rhs: CameraTarget) -> Bool {
            lhs.id == rhs.id
        }
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true

        let cacheDir = Self.tileCacheDirectory()
        let overlay = CachedTileOverlay(
            urlTemplate: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
            cacheDirectory: cacheDir
        )
        overlay.canReplaceMapContent = true
        overlay.maximumZ = 17
        overlay.minimumZ = 1
        map.addOverlay(overlay, level: .aboveLabels)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userGestured(_:)))
        pan.delegate = context.coordinator
        map.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userGestured(_:)))
        pinch.delegate = context.coordinator
        map.addGestureRecognizer(pinch)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        let existingPolylines = map.overlays.compactMap { $0 as? MKPolyline }
        if !existingPolylines.isEmpty {
            map.removeOverlays(existingPolylines)
        }

        for segment in segments where segment.count >= 2 {
            var coords = segment
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            map.addOverlay(polyline, level: .aboveLabels)
        }

        let startEndAnnotations = map.annotations.compactMap { $0 as? RouteEndpointAnnotation }
        if !startEndAnnotations.isEmpty {
            map.removeAnnotations(startEndAnnotations)
        }

        let tracks = segments.filter { $0.count >= 2 }
        if let firstCoord = tracks.first?.first {
            map.addAnnotation(RouteEndpointAnnotation(coordinate: firstCoord, title: "Start", kind: .start))
        }
        if let lastCoord = tracks.last?.last, tracks.flatMap({ $0 }).count >= 2 {
            map.addAnnotation(RouteEndpointAnnotation(coordinate: lastCoord, title: "End", kind: .end))
        }

        if let target = cameraTarget, context.coordinator.lastAppliedTargetID != target.id {
            context.coordinator.lastAppliedTargetID = target.id
            context.coordinator.isProgrammaticChange = true

            switch target.kind {
            case let .region(region):
                map.setRegion(region, animated: true)
            case let .mapRect(rect):
                let padded = rect.insetBy(
                    dx: -rect.size.width * 0.1,
                    dy: -rect.size.height * 0.1
                )
                map.setVisibleMapRect(padded, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private static func tileCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("OpenTopoMapTiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TopoMapView
        var lastAppliedTargetID: UUID?
        var isProgrammaticChange = false

        init(parent: TopoMapView) {
            self.parent = parent
        }

        @objc func userGestured(_ recognizer: UIGestureRecognizer) {
            if recognizer.state == .began {
                parent.onUserInteraction()
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
            isProgrammaticChange = false
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            guard let endpoint = annotation as? RouteEndpointAnnotation else {
                return nil
            }

            let identifier = "RouteEndpoint"
            let view: MKMarkerAnnotationView
            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView {
                dequeued.annotation = annotation
                view = dequeued
            } else {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }

            switch endpoint.kind {
            case .start:
                view.markerTintColor = .systemGreen
                view.glyphText = "S"
            case .end:
                view.markerTintColor = .systemRed
                view.glyphText = "E"
            }
            view.canShowCallout = true
            return view
        }
    }
}

final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case start
        case end
    }

    let coordinate: CLLocationCoordinate2D
    let title: String?
    let kind: Kind

    init(coordinate: CLLocationCoordinate2D, title: String?, kind: Kind) {
        self.coordinate = coordinate
        self.title = title
        self.kind = kind
    }
}

final class CachedTileOverlay: MKTileOverlay {
    private let cacheDirectory: URL
    private let session: URLSession

    init(urlTemplate: String?, cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        super.init(urlTemplate: urlTemplate)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let filename = "\(path.z)_\(path.x)_\(path.y)@\(path.contentScaleFactor).png"
        let cacheFile = cacheDirectory.appendingPathComponent(filename)

        if let data = try? Data(contentsOf: cacheFile), !data.isEmpty {
            result(data, nil)
            return
        }

        let url = self.url(forTilePath: path)
        var request = URLRequest(url: url)
        request.setValue("tracker-ios/1.0 (personal hiking app)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { data, response, error in
            if let data = data,
               let http = response as? HTTPURLResponse,
               http.statusCode == 200,
               !data.isEmpty {
                try? data.write(to: cacheFile, options: .atomic)
                result(data, nil)
            } else {
                result(data, error)
            }
        }
        task.resume()
    }
}
