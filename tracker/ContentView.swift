//
//  ContentView.swift
//  tracker
//
//  Created by 신정열 on 4/21/26.
//

import SwiftUI
import Foundation
import MapKit

struct ContentView: View {
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var loadMessage = "sample.gpx를 프로젝트에 추가하면 경로가 표시됩니다."

    var body: some View {
        VStack(spacing: 12) {
            Map(position: $cameraPosition) {
                if routeCoordinates.count == 1, let coordinate = routeCoordinates.first {
                    Marker("Start", coordinate: coordinate)
                }

                if routeCoordinates.count >= 2 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(.blue, lineWidth: 4)

                    Marker("Start", coordinate: routeCoordinates[0])
                    Marker("End", coordinate: routeCoordinates[routeCoordinates.count - 1])
                }
            }
            .mapStyle(.standard)
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
            cameraPosition = .rect(Self.mapRect(for: points))
            loadMessage = "총 \(points.count)개 좌표를 지도에 표시했습니다."
        } catch {
            loadMessage = "GPX 파싱 실패: \(error.localizedDescription)"
        }
    }

    private static func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let points = coordinates.map(MKMapPoint.init)

        guard var rect = points.first.map({ MKMapRect(origin: $0, size: MKMapSize(width: 0, height: 0)) }) else {
            return .world
        }

        for point in points.dropFirst() {
            let pointRect = MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0))
            rect = rect.union(pointRect)
        }

        return rect.insetBy(dx: -rect.size.width * 0.2 - 500, dy: -rect.size.height * 0.2 - 500)
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
