import MapKit
import SwiftUI

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @StateObject private var search = PlaceSearchCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeStart: CLLocationCoordinate2D?
    @State private var routeEnd: CLLocationCoordinate2D?
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var isRouting = false
    @State private var routeRequestTask: Task<Void, Never>?
    @State private var routeRequestID = UUID()
    @State private var searchSelectionTask: Task<Void, Never>?
    @State private var searchSelectionID = UUID()
    @State private var showRouteSheet = false
    @State private var showGPXImporter = false
    @State private var drawnPath: [CLLocationCoordinate2D] = []
    @State private var drawMode = false
    @State private var pinSelected = false
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?

    private var mapStyle: MapStyle {
        switch session.mapStyleIndex {
        case 1: return .hybrid(elevation: .realistic)
        case 2: return .imagery(elevation: .realistic)
        default: return .standard(elevation: .realistic)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep Map inside the safe layout bounds so MapProxy.convert matches
            // finger position. Ignoring the safe area makes the tiles full-bleed but
            // shifts convert() upward by ~status-bar height.
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    if let pin = session.pin {
                        Annotation("", coordinate: pin, anchor: .bottom) {
                            MapDropPin(
                                selected: pinSelected,
                                isDragging: isDraggingPin,
                                onSelect: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onRemove: {
                                    suppressNextMapTap = true
                                    withAnimation {
                                        session.pin = nil
                                        pinPlaceName = nil
                                        pinSelected = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onDragBegan: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    pinSelected = false
                                    isDraggingPin = true
                                },
                                onDragMoved: { globalPoint in
                                    if let coord = proxy.convert(globalPoint, from: .global) {
                                        session.pin = coord
                                    }
                                },
                                onDragEnded: {
                                    isDraggingPin = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        suppressNextMapTap = false
                                    }
                                }
                            )
                        }
                    }
                    if let sim = session.simulated {
                        Annotation("Spoof", coordinate: sim) {
                            ZStack {
                                Circle().fill(KladzTheme.accent.opacity(0.25)).frame(width: 44, height: 44)
                                Circle().fill(KladzTheme.accent).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    if routeCoords.count > 1 {
                        MapPolyline(coordinates: routeCoords)
                            .stroke(KladzTheme.accent, lineWidth: 5)
                    }
                    if drawnPath.count > 1 {
                        MapPolyline(coordinates: drawnPath)
                            .stroke(KladzTheme.accentSecondary, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                    }
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    placePin(at: point, proxy: proxy)
                }
            }
            .background(Color.black.ignoresSafeArea())

            topChrome
        }
        .onAppear {
            session.startLocationUpdates()
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil { pinSelected = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kladzImportGPX)) { note in
            guard let url = note.object as? URL else { return }
            importGPX(url)
        }
        .fileImporter(isPresented: $showGPXImporter, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importGPX(url)
            }
        }
        .sheet(isPresented: $showRouteSheet) {
            RoutePlannerSheet(
                start: $routeStart,
                end: $routeEnd,
                isRouting: $isRouting,
                onBuild: buildRoadRoute,
                onPlay: playRoute,
                onImportGPX: { showGPXImporter = true },
                onExportGPX: exportGPX,
                onUseDrawn: {
                    routeCoords = RouteBuilder.sample(coordinates: drawnPath, every: 10)
                    drawnPath.removeAll()
                    drawMode = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func placePin(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        if drawMode {
            drawnPath.append(coord)
        } else {
            session.pin = coord
            pinPlaceName = nil
            pinSelected = false
        }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            StatusBarView()

            searchBar

            if !searchText.isEmpty && !search.results.isEmpty {
                searchResults
            }

            HStack(alignment: .center, spacing: 10) {
                mapChromeButtons
                Spacer(minLength: 0)
                locateButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .safeAreaPadding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search places", text: $searchText)
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                }
                .onChange(of: searchText) { _, value in
                    // Invalidate a place lookup when the user changes or clears the query.
                    searchSelectionTask?.cancel()
                    searchSelectionTask = nil
                    searchSelectionID = UUID()
                    search.query = value
                }
            if searchFocused || !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear and dismiss keyboard")
            }
            if searchFocused {
                Button("Done") {
                    searchFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(KladzTheme.accent)
            }
        }
        .padding(12)
        .kladzGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(search.results.prefix(5), id: \.self) { item in
                Button {
                    select(completion: item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
        .kladzGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapChromeButtons: some View {
        HStack(spacing: 4) {
            chromeIconButton("square.3.layers.3d") {
                session.mapStyleIndex = (session.mapStyleIndex + 1) % 3
            }
            chromeIconButton("point.topleft.down.to.point.bottomright.curvepath") {
                showRouteSheet = true
            }
            chromeIconButton(drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle") {
                drawMode.toggle()
                if !drawMode { drawnPath.removeAll() }
            }
            .foregroundStyle(drawMode ? KladzTheme.accentSecondary : .primary)

            if session.pin != nil {
                chromeIconButton("star.circle") {
                    if let pin = session.pin {
                        let name = session.suggestedFavoriteName(for: pin, fallback: pinPlaceName)
                        session.addFavorite(name: name, coordinate: pin)
                    }
                }
            }
        }
        .padding(6)
        .kladzGlass(.clear, in: Capsule())
        .contentShape(Capsule())
    }

    private var locateButton: some View {
        Button {
            searchFocused = false
            goToCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .kladzGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
        .contentShape(Circle())
        .accessibilityLabel("Current location")
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        let meters: CLLocationDistance = 900
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: sim,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realCoordinate {
                position = .region(MKCoordinateRegion(
                    center: real,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))
                )
            }
        }
    }

    private func chromeIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func select(completion: MKLocalSearchCompletion) {
        searchSelectionTask?.cancel()
        let requestID = UUID()
        searchSelectionID = requestID
        searchFocused = false

        searchSelectionTask = Task {
            let request = MKLocalSearch.Request(completion: completion)
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled, let item = response.mapItems.first else { return }
                let coordinate = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate) else { return }
                let title = item.name ?? completion.title

                await MainActor.run {
                    // A slower lookup must not replace a newer selection.
                    guard !Task.isCancelled, searchSelectionID == requestID else { return }
                    session.pin = coordinate
                    pinPlaceName = title
                    position = .region(MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 1200,
                        longitudinalMeters: 1200
                    ))
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                    session.addFavorite(name: title, coordinate: coordinate)
                    session.pushNamedRecent(name: title, coordinate: coordinate)
                    searchSelectionTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard searchSelectionID == requestID else { return }
                    session.lastError = "Couldn’t load that place. Check your connection and try again."
                    searchSelectionTask = nil
                }
            }
        }
    }

    private func buildRoadRoute() {
        guard let start = routeStart ?? session.simulated ?? session.pin,
              let end = routeEnd else {
            session.lastError = "Set a route start and end."
            return
        }

        // A slower previous search must never overwrite the user's newer route request.
        routeRequestTask?.cancel()
        let requestID = UUID()
        routeRequestID = requestID
        routeCoords = []
        isRouting = true

        routeRequestTask = Task {
            do {
                let coords = try await RouteBuilder.roadRoute(from: start, to: end, mode: session.travelMode)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard routeRequestID == requestID else { return }
                    routeCoords = coords
                    isRouting = false
                    routeRequestTask = nil
                }
            } catch {
                await MainActor.run {
                    guard routeRequestID == requestID else { return }
                    isRouting = false
                    routeRequestTask = nil
                    if !(error is CancellationError) {
                        session.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func playRoute() {
        let path = routeCoords.isEmpty ? drawnPath : routeCoords
        guard path.count >= 2 else {
            session.lastError = "Build or draw a route first."
            return
        }
        showRouteSheet = false
        session.followRoute(path, pairing: pairing)
    }

    private func importGPX(_ url: URL) {
        do {
            let coords = try GPXCodec.parse(url)
            routeCoords = RouteBuilder.sample(coordinates: coords, every: 10)
            if let first = coords.first {
                session.pin = first
                position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000))
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    private func exportGPX() {
        let path = routeCoords.isEmpty ? drawnPath : routeCoords
        guard !path.isEmpty else {
            session.lastError = "Nothing to export."
            return
        }
        let gpx = GPXCodec.export(path)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kladz-Route-\(UUID().uuidString).gpx")
        do {
            try Data(gpx.utf8).write(to: url, options: .atomic)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            av.completionWithItemsHandler = { _, _, _, _ in
                // The share sheet has finished using the temporary export.
                try? FileManager.default.removeItem(at: url)
            }
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                // iPad requires a popover anchor for activity sheets.
                if let popover = av.popoverPresentationController {
                    popover.sourceView = root.view
                    popover.sourceRect = CGRect(
                        x: root.view.bounds.midX,
                        y: root.view.bounds.midY,
                        width: 0,
                        height: 0
                    )
                    popover.permittedArrowDirections = []
                }
                root.present(av, animated: true)
            } else {
                try? FileManager.default.removeItem(at: url)
                session.lastError = "Could not open the share sheet."
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet {
            results = []
            completer.queryFragment = query
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        let completedQuery = completer.queryFragment
        Task { @MainActor in
            guard completedQuery == self.query else { return }
            self.results = items
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let failedQuery = completer.queryFragment
        Task { @MainActor in
            guard failedQuery == self.query else { return }
            self.results = []
        }
    }
}
