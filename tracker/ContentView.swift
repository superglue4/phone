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
    @State private var gpxFiles: [GPXFileItem] = []
    @State private var selectedFile: GPXFileItem?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var loadMessage = "`gpx` 폴더를 프로젝트 리소스로 추가하면 목록이 표시됩니다."

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Menu {
                    if gpxFiles.isEmpty {
                        Text("gpx 폴더에서 파일을 찾지 못했습니다.")
                    } else {
                        ForEach(groupedFiles.keys.sorted(), id: \.self) { group in
                            Section(group) {
                                ForEach(groupedFiles[group] ?? []) { file in
                                    Button(file.displayName) {
                                        loadGPXFile(file)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Label(selectedFile?.relativePath ?? "GPX 파일 선택", systemImage: "folder")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                if let selectedFile {
                    Button("다시 읽기") {
                        loadGPXFile(selectedFile)
                    }
                    .buttonStyle(.bordered)
                }
            }

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
            discoverGPXFiles()
        }
    }

    private var groupedFiles: [String: [GPXFileItem]] {
        Dictionary(grouping: gpxFiles, by: \.groupName)
    }

    private func discoverGPXFiles() {
        do {
            gpxFiles = try GPXFileItem.discoverAll()

            guard let first = gpxFiles.first else {
                routeCoordinates = []
                selectedFile = nil
                loadMessage = "Xcode에서 `gpx` 폴더를 tracker 타깃 리소스로 추가하세요."
                return
            }

            loadGPXFile(first)
        } catch {
            routeCoordinates = []
            selectedFile = nil
            loadMessage = "GPX 목록 읽기 실패: \(error.localizedDescription)"
        }
    }

    private func loadGPXFile(_ file: GPXFileItem) {
        selectedFile = file

        do {
            let points = try GPXParser.parse(contentsOf: file.url)

            guard !points.isEmpty else {
                routeCoordinates = []
                loadMessage = "\(file.relativePath): trkpt 좌표가 없습니다."
                return
            }

            routeCoordinates = points
            cameraPosition = .rect(Self.mapRect(for: points))
            loadMessage = "\(file.relativePath)에서 \(points.count)개 좌표를 표시했습니다."
        } catch {
            routeCoordinates = []
            loadMessage = "\(file.relativePath) 파싱 실패: \(error.localizedDescription)"
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

private struct GPXFileItem: Identifiable, Hashable {
    let relativePath: String
    let url: URL

    var id: String { relativePath }
    var displayName: String { url.deletingPathExtension().lastPathComponent }

    var groupName: String {
        let folder = (relativePath as NSString).deletingLastPathComponent
        return folder.isEmpty || folder == "." ? "기타" : folder
    }

    static func discoverAll() throws -> [GPXFileItem] {
        guard let baseURL = Bundle.main.resourceURL?.appendingPathComponent("gpx", isDirectory: true) else {
            return []
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: baseURL.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .map { url in
                let relativePath = url.path.replacingOccurrences(of: baseURL.path + "/", with: "")
                return GPXFileItem(relativePath: relativePath, url: url)
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
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
