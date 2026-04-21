//
//  ContentView.swift
//  tracker
//
//  Created by 신정열 on 4/21/26.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var loadMessage = "sample.gpx를 프로젝트에 추가하면 경로가 표시됩니다."

    var body: some View {
        VStack(spacing: 12) {
            GPXMapView(coordinates: routeCoordinates)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(loadMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .task {
            loadGPX()
        }
    }

    private func loadGPX() {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "gpx") else {
            loadMessage = "Xcode에서 sample.gpx를 tracker 타깃에 추가하세요."
            return
        }

        do {
            let points = try GPXParser.parse(contentsOf: url)

            guard !points.isEmpty else {
                loadMessage = "GPX는 읽었지만 trkpt 좌표가 없습니다."
                return
            }

            routeCoordinates = points
            loadMessage = "총 \(points.count)개 좌표를 지도에 표시했습니다."
        } catch {
            loadMessage = "GPX 파싱 실패: \(error.localizedDescription)"
        }
    }
}

private struct GPXMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .excludingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)

        guard coordinates.count >= 2 else {
            if let coordinate = coordinates.first {
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ),
                    animated: true
                )
            }
            return
        }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 40, left: 20, bottom: 40, right: 20),
            animated: true
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 4
            return renderer
        }
    }
}

private enum GPXParserError: Error {
    case invalidFile
}

private final class GPXParser: NSObject, XMLParserDelegate {
    private var points: [CLLocationCoordinate2D] = []

    static func parse(contentsOf url: URL) throws -> [CLLocationCoordinate2D] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw GPXParserError.invalidFile
        }

        let delegate = GPXParser()
        parser.delegate = delegate

        if parser.parse() {
            return delegate.points
        } else {
            throw parser.parserError ?? GPXParserError.invalidFile
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        guard elementName == "trkpt" || elementName == "rtept" || elementName == "wpt" else {
            return
        }

        guard
            let latString = attributeDict["lat"],
            let lonString = attributeDict["lon"],
            let latitude = Double(latString),
            let longitude = Double(lonString)
        else {
            return
        }

        points.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }
}

#Preview {
    ContentView()
}
