//
//  ContentView.swift
//  tracker
//
//  Created by 신정열 on 4/21/26.
//

import SwiftUI
import Foundation
import MapKit
import CoreLocation
import Combine

struct ContentView: View {
    @State private var gpxFiles: [GPXFileItem] = []
    @State private var selectedFile: GPXFileItem?
    @State private var routeSegments: [[CLLocationCoordinate2D]] = []
    @State private var cameraTarget: TopoMapView.CameraTarget?
    @State private var visibleSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    @State private var loadMessage = "GPX를 선택하십시오."
    @State private var isFollowingUserLocation = true
    @AppStorage("lastSelectedGPXPath") private var lastSelectedGPXPath: String = ""
    @State private var isShowingGPXPicker = false
    @State private var gpxSearchText = ""
    @State private var debouncedSearchText = ""
    @StateObject private var locationManager = LocationManager()
    @StateObject private var watchBridge = PhoneWatchBridge.shared

    var body: some View {
        VStack(spacing: 12) {
            controlsBar

            ZStack(alignment: .bottomTrailing) {
                TopoMapView(
                    segments: routeSegments,
                    userCoordinate: locationManager.coordinate,
                    cameraTarget: cameraTarget,
                    onRegionChange: { region in
                        visibleSpan = region.span
                    },
                    onUserInteraction: {
                        if isFollowingUserLocation {
                            isFollowingUserLocation = false
                        }
                    }
                )

                Text("© OpenTopoMap · © OpenStreetMap")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding()
        .task {
            discoverGPXFiles()
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        }
        .onReceive(locationManager.$coordinate) { _ in
            guard isFollowingUserLocation else {
                return
            }

            moveCameraToUserLocation()
        }
        .onChange(of: gpxSearchText) { _, newValue in
            scheduleSearchDebounce(for: newValue)
        }
        .sheet(isPresented: $isShowingGPXPicker) {
            NavigationStack {
                List {
                    Section(filteredFilesTitle) {
                        if isSearchEmpty {
                            Text("검색어를 입력하면 GPX 파일이 1개씩 표시됩니다.")
                                .foregroundStyle(.secondary)
                        } else if filteredFiles.isEmpty {
                            Text("검색 결과가 없습니다.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredFiles) { file in
                                Button {
                                    loadGPXFile(file)
                                    isShowingGPXPicker = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.displayName)
                                                .foregroundStyle(.primary)
                                            Text(file.cleanedRelativePath)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if selectedFile == file {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("GPX 선택")
                .searchable(text: $gpxSearchText, prompt: "대분류, 중분류, 파일 검색")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") {
                            isShowingGPXPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .safeAreaInset(edge: .bottom) {
            bottomStatusPanel
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            Button {
                gpxSearchText = ""
                debouncedSearchText = ""
                isShowingGPXPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "map")
                    Text(selectedFile?.cleanedRelativePath ?? "GPX를 선택하십시오")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)

            Button {
                isFollowingUserLocation = true
                locationManager.startUpdatingLocation()
                moveCameraToUserLocation()
            } label: {
                Label("내 위치", systemImage: "location.fill")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .zIndex(1)
    }

    private var filteredFiles: [GPXFileItem] {
        let keyword = normalizedSearchText(debouncedSearchText)

        guard !keyword.isEmpty else {
            return []
        }

        return gpxFiles.filter { file in
            file.normalizedSearchText.contains(keyword)
        }
    }

    private var isSearchEmpty: Bool {
        normalizedSearchText(debouncedSearchText).isEmpty
    }

    private var filteredFilesTitle: String {
        isSearchEmpty ? "GPX 검색" : "검색 결과 \(filteredFiles.count)건"
    }

    private var flattenedRouteCoordinates: [CLLocationCoordinate2D] {
        routeSegments.filter { $0.count >= 2 }.flatMap { $0 }
    }

    private var bottomStatusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(selectedFile?.displayName ?? "선택된 GPX 없음", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                if let selectedFile {
                    Button {
                        loadGPXFile(selectedFile)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text(selectedFile?.cleanedRelativePath ?? "GPX 파일을 선택하면 경로를 표시합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Divider()

            Text(locationStatusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(loadMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "위치 권한을 요청하는 중입니다."
        case .restricted:
            return "이 기기에서는 위치 접근이 제한되어 있습니다."
        case .denied:
            return "위치 권한이 거부되었습니다. 설정에서 tracker 위치 권한을 허용하세요."
        case .authorizedAlways, .authorizedWhenInUse:
            if let coordinate = locationManager.coordinate {
                let modeText = isFollowingUserLocation ? "자동 추적 중" : "지도는 수동 조작 중"
                return String(format: "현재 위치: %.6f, %.6f", coordinate.latitude, coordinate.longitude) + " · \(modeText)"
            }

            if let errorMessage = locationManager.lastErrorMessage {
                return "현재 위치를 가져오지 못했습니다: \(errorMessage)"
            }

            return "GPS에서 현재 위치를 읽는 중입니다."
        @unknown default:
            return "위치 상태를 확인할 수 없습니다."
        }
    }

    private func discoverGPXFiles() {
        do {
            gpxFiles = try GPXFileItem.discoverAll()

            guard !gpxFiles.isEmpty else {
                routeSegments = []
                selectedFile = nil
                loadMessage = "Xcode에서 `gpx` 폴더를 tracker 타깃 리소스로 추가하세요."
                return
            }

            if !lastSelectedGPXPath.isEmpty,
               let saved = gpxFiles.first(where: { $0.relativePath == lastSelectedGPXPath }) {
                loadGPXFile(saved)
            } else {
                routeSegments = []
                selectedFile = nil
                loadMessage = "GPX를 선택하십시오."
            }
        } catch {
            routeSegments = []
            selectedFile = nil
            loadMessage = "GPX 목록 읽기 실패: \(error.localizedDescription)"
        }
    }

    private func loadGPXFile(_ file: GPXFileItem) {
        selectedFile = file
        lastSelectedGPXPath = file.relativePath

        do {
            let parsed = try GPXParser.parse(contentsOf: file.url)
            let segments = Self.splitLargeGaps(in: parsed)
            let points = segments.filter { $0.count >= 2 }.flatMap { $0 }

            guard !points.isEmpty else {
                routeSegments = []
                loadMessage = "\(file.cleanedRelativePath): trkpt 좌표가 없습니다."
                return
            }

            routeSegments = segments
            isFollowingUserLocation = false
            cameraTarget = .mapRect(Self.mapRect(for: points))
            watchBridge.sendRoute(name: file.displayName, segments: segments)
            loadMessage = "\(file.cleanedRelativePath)에서 \(segments.count)개 경로, \(points.count)개 좌표를 표시했습니다."
        } catch {
            routeSegments = []
            loadMessage = "\(file.cleanedRelativePath) 파싱 실패: \(error.localizedDescription)"
        }
    }

    private static func splitLargeGaps(
        in segments: [[CLLocationCoordinate2D]],
        maxGapMeters: Double = 500
    ) -> [[CLLocationCoordinate2D]] {
        var result: [[CLLocationCoordinate2D]] = []

        for segment in segments {
            guard segment.count > 1 else {
                result.append(segment)
                continue
            }

            var current: [CLLocationCoordinate2D] = [segment[0]]

            for i in 1..<segment.count {
                let prev = CLLocation(latitude: segment[i - 1].latitude, longitude: segment[i - 1].longitude)
                let next = CLLocation(latitude: segment[i].latitude, longitude: segment[i].longitude)

                if prev.distance(from: next) > maxGapMeters {
                    result.append(current)
                    current = [segment[i]]
                } else {
                    current.append(segment[i])
                }
            }

            if !current.isEmpty {
                result.append(current)
            }
        }

        return result
    }

    private func moveCameraToUserLocation() {
        guard let coordinate = locationManager.coordinate else {
            return
        }

        cameraTarget = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: visibleSpan
            )
        )
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

    private func scheduleSearchDebounce(for text: String) {
        let latest = text

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))

            guard latest == gpxSearchText else {
                return
            }

            debouncedSearchText = latest
        }
    }

    private func normalizedSearchText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
private final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastErrorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestWhenInUseAuthorization() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestCurrentLocation() {
        lastErrorMessage = nil

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            lastErrorMessage = "권한이 없어 GPS를 사용할 수 없습니다."
        @unknown default:
            lastErrorMessage = "알 수 없는 위치 권한 상태입니다."
        }
    }

    func startUpdatingLocation() {
        lastErrorMessage = nil

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            lastErrorMessage = "권한이 없어 GPS를 사용할 수 없습니다."
        @unknown default:
            lastErrorMessage = "알 수 없는 위치 권한 상태입니다."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            coordinate = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorMessage = error.localizedDescription
    }
}

nonisolated private struct GPXFileItem: Identifiable, Hashable {
    let relativePath: String
    let url: URL
    let normalizedSearchText: String

    var id: String { relativePath }
    var pathComponents: [String] {
        relativePath.split(separator: "/").map(String.init)
    }

    var displayName: String {
        Self.cleanedFileName(url.deletingPathExtension().lastPathComponent)
    }

    var topLevelName: String {
        pathComponents.first.map(Self.cleanedFolderName) ?? "기타"
    }

    var secondLevelName: String {
        guard pathComponents.count >= 3 else {
            return ""
        }

        return Self.cleanedFolderName(pathComponents[1])
    }

    var cleanedRelativePath: String {
        var cleaned = [topLevelName]

        if !secondLevelName.isEmpty {
            cleaned.append(secondLevelName)
        }

        cleaned.append(displayName)
        return cleaned.joined(separator: " / ")
    }

    var searchText: String {
        [topLevelName, secondLevelName, displayName, cleanedRelativePath]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
                let item = GPXFileItem(
                    relativePath: relativePath,
                    url: url,
                    normalizedSearchText: ""
                )

                return GPXFileItem(
                    relativePath: relativePath,
                    url: url,
                    normalizedSearchText: item.searchText
                        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                )
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func cleanedFolderName(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"^\d+[\s_-]*"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func cleanedFileName(_ name: String) -> String {
        let withoutTrailingNumber = name.replacingOccurrences(
            of: #"([_-]?\d+)+$"#,
            with: "",
            options: .regularExpression
        )

        return cleanedFolderName(withoutTrailingNumber)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
    }
}

private enum GPXParserError: Error {
    case invalidFile
}

private final class GPXParser: NSObject, XMLParserDelegate {
    private var segments: [[CLLocationCoordinate2D]] = []
    private var currentSegment: [CLLocationCoordinate2D] = []
    private var currentContainer: String?

    static func parse(contentsOf url: URL) throws -> [[CLLocationCoordinate2D]] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw GPXParserError.invalidFile
        }

        let delegate = GPXParser()
        parser.delegate = delegate

        if parser.parse() {
            return delegate.segments
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
        if elementName == "trk" || elementName == "trkseg" || elementName == "rte" {
            closeCurrentSegment()
            currentContainer = elementName
            return
        }

        if elementName == "wpt" {
            closeCurrentSegment()
            if let coordinate = Self.coordinate(from: attributeDict) {
                segments.append([coordinate])
            }
            return
        }

        guard elementName == "trkpt" || elementName == "rtept" else {
            return
        }

        guard let coordinate = Self.coordinate(from: attributeDict) else {
            return
        }

        currentSegment.append(coordinate)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "trkseg" || elementName == "trk" || elementName == "rte" else {
            return
        }

        closeCurrentSegment()

        if currentContainer == elementName {
            currentContainer = nil
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        closeCurrentSegment()
    }

    private func closeCurrentSegment() {
        guard !currentSegment.isEmpty else {
            return
        }

        segments.append(currentSegment)
        currentSegment.removeAll(keepingCapacity: true)
    }

    private static func coordinate(from attributes: [String : String]) -> CLLocationCoordinate2D? {
        guard
            let latString = attributes["lat"],
            let lonString = attributes["lon"],
            let latitude = Double(latString),
            let longitude = Double(lonString)
        else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
