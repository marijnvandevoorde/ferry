import FerryKit
import QuickLook
import SwiftUI

struct GalleryView: View {
    @Environment(CameraModel.self) private var model
    @State private var filter = Filter.all
    /// The item last clicked; space previews it.
    @State private var focusedItem: PhotoItem?
    @State private var previewURL: URL?
    @AppStorage(Prefs.sortOldestFirst) private var oldestFirst = false
    @AppStorage(Prefs.thumbnailSize) private var thumbnailSize = 170.0

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", new = "Not Imported"
        var id: String { rawValue }
    }

    private var visibleItems: [PhotoItem] {
        (filter == .new ? model.newItems : model.items).filter(model.matchesFilters)
    }

    private var sections: [(day: Date, items: [PhotoItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visibleItems) { calendar.startOfDay(for: $0.date) }
        let days = groups.keys.sorted(by: >)
        // The model lists newest first.
        return (oldestFirst ? days.reversed() : days).map { ($0, oldestFirst ? groups[$0]!.reversed() : groups[$0]!) }
    }

    private static let kinds: [(ObjectInfo.Kind?, LocalizedStringKey)] = [
        (nil, "All Types"), (.jpeg, "JPEG"), (.raw, "RAW"), (.heif, "HEIF"), (.video, "Videos"),
    ]

    var body: some View {
        @Bindable var model = model
        ScrollView {
            if visibleItems.isEmpty && !model.isListing {
                ContentUnavailableView(filter == .new ? "Nothing new to bring across" : "No photos on the card",
                                       systemImage: filter == .new ? "checkmark.circle" : "photo.on.rectangle.angled")
                    .padding(.top, 120)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize * 1.4), spacing: 10)], spacing: 10,
                      pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.day) { section in
                    Section {
                        ForEach(section.items) { item in
                            PhotoCell(item: item, isSelected: model.selection.contains(item.id),
                                      isFocused: focusedItem?.id == item.id)
                                .onTapGesture(count: 2) { preview(item) }
                                .onTapGesture { toggle(item) }
                                .contextMenu { contextMenu(for: item) }
                                .accessibilityAction { toggle(item) }
                                .accessibilityAction(named: "Preview") { preview(item) }
                        }
                    } header: {
                        SectionHeader(day: section.day, items: section.items)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let focusedItem else { return .ignored }
            preview(focusedItem)
            return .handled
        }
        .onKeyPress(.return) {
            guard let focusedItem else { return .ignored }
            toggle(focusedItem)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            moveFocus(by: press.key == .leftArrow || press.key == .upArrow ? -1 : 1)
            return .handled
        }
        .quickLookPreview($previewURL)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if model.showBacklogNotice { BacklogNotice() }
                if model.showResizeNotice { ResizeNotice() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ImportBar()
        }
        .navigationTitle(model.cameraName.isEmpty ? "Camera" : model.cameraName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItemGroup {
                Slider(value: $thumbnailSize, in: 110...320)
                    .frame(width: 90)
                    .help("Thumbnail size")
                Menu {
                    Picker("Type", selection: $model.kindFilter) {
                        ForEach(Self.kinds, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.inline)
                    Toggle("Only Protected Photos", isOn: $model.protectedOnly)
                    Divider()
                    Picker("Order", selection: $oldestFirst) {
                        Text("Newest First").tag(false)
                        Text("Oldest First").tag(true)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Filter", systemImage: model.kindFilter != nil || model.protectedOnly
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help("Filter and sort. Import New imports what the filters show.")
                Menu {
                    Button("Select All") { model.selection = Set(visibleItems.map(\.id)) }
                        .keyboardShortcut("a")
                    Button("Select Not Imported") { model.selection = Set(model.newItems.map(\.id)) }
                    Button("Deselect All") { model.selection = [] }
                        .keyboardShortcut("d")
                    Divider()
                    Button("Mark Selected as Imported") { model.markImported(model.selection, true) }
                        .disabled(model.selection.isEmpty)
                    Button("Mark Selected as Not Imported") { model.markImported(model.selection, false) }
                        .disabled(model.selection.isEmpty)
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                Button {
                    model.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "eject")
                }
                .help("Disconnect from the camera")
            }
        }
    }

    private var subtitle: String {
        if model.isListing {
            return String(localized: "Reading card… \(model.listProgress.loaded) of \(model.listProgress.total)")
        }
        let n = model.items.count
        let new = model.newItems.count
        return String(localized: "\(n) items · \(new) not imported")
    }

    /// Arrow keys step through the photos in display order.
    private func moveFocus(by offset: Int) {
        let ordered = sections.flatMap(\.items)
        guard !ordered.isEmpty else { return }
        let current = focusedItem.flatMap { item in ordered.firstIndex { $0.id == item.id } }
        let next = current.map { min(max($0 + offset, 0), ordered.count - 1) } ?? 0
        focusedItem = ordered[next]
        if previewURL != nil { preview(ordered[next]) }
    }

    private func preview(_ item: PhotoItem) {
        focusedItem = item
        Task { previewURL = await model.previewFile(for: item) }
    }

    /// Acts on the whole selection when the clicked photo is part of it, like the Finder.
    @ViewBuilder private func contextMenu(for item: PhotoItem) -> some View {
        let ids = model.selection.contains(item.id) ? model.selection : [item.id]
        let targets = model.items.filter { ids.contains($0.id) }
        Button(ids.count > 1 ? "Import \(ids.count) Photos" : "Import") {
            model.startImport(targets)
        }
        .disabled(model.isImporting)
        if !item.info.isVideo {
            Button("Quick Look") { preview(item) }
        }
        Divider()
        if targets.contains(where: { !$0.imported }) {
            Button("Mark as Imported") { model.markImported(ids, true) }
        }
        if targets.contains(where: \.imported) {
            Button("Mark as Not Imported") { model.markImported(ids, false) }
        }
    }

    private func toggle(_ item: PhotoItem) {
        focusedItem = item
        if model.selection.contains(item.id) {
            model.selection.remove(item.id)
        } else {
            model.selection.insert(item.id)
        }
    }
}

private struct SectionHeader: View {
    @Environment(CameraModel.self) private var model
    let day: Date
    let items: [PhotoItem]

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Button(allSelected ? "Deselect" : "Select") {
                let ids = Set(items.map(\.id))
                if allSelected {
                    model.selection.subtract(ids)
                } else {
                    model.selection.formUnion(ids)
                }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var allSelected: Bool {
        items.allSatisfy { model.selection.contains($0.id) }
    }

    private var title: String {
        if day == Calendar.current.startOfDay(for: .distantPast) { return String(localized: "Unknown date") }
        if Calendar.current.isDateInToday(day) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

private struct BacklogNotice: View {
    @Environment(CameraModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray.full")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Already copied these photos some other way?")
                    .font(.headline)
                Text("Mark them as imported, and Import New will only pick up photos you take from now on. Nothing is copied or deleted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Mark All as Imported") {
                model.markImported(Set(model.items.map(\.id)), true)
            }
            Button {
                model.dismissBacklogNotice()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct ResizeNotice: View {
    @Environment(CameraModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("The camera is sending smaller copies of your photos")
                    .font(.headline)
                Text("To get full-size photos, turn off **Resize Img for Smartphone** on the camera. It's under Set Up → Connection Setting → General Settings on most models.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Don't Show Again") { model.dismissResizeNotice(forever: true) }
            Button {
                model.dismissResizeNotice(forever: false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct ImportBar: View {
    @Environment(CameraModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                if let p = model.importProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        if p.total == 0 {
                            // Selection sent from the camera: the total isn't known up front.
                            Text(p.index == 0 ? "Waiting for the camera to send images…" : "Receiving \(p.filename) — \(p.index)")
                                .font(.callout)
                                .lineLimit(1)
                            ProgressView(value: p.fraction)
                        } else {
                            HStack {
                                Text("Importing \(p.filename) — \(p.index) of \(p.total)")
                                    .lineLimit(1)
                                Spacer()
                                if let speed = p.speed {
                                    Text(Self.rate(speed, remaining: p.timeRemaining))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                            ProgressView(value: p.totalBytes > 0 ? Double(p.bytesDone) / Double(p.totalBytes)
                                         : (Double(p.index - 1) + p.fraction) / Double(max(p.total, 1)))
                        }
                    }
                    Button("Stop") { model.cancelImport() }
                } else {
                    status
                    Spacer()
                    if !model.selection.isEmpty {
                        Button("Import \(model.selection.count) Selected") { model.importSelected() }
                    }
                    Button {
                        model.importNew()
                    } label: {
                        Text(model.itemsToImport.isEmpty ? "No New Items" : "Import \(model.itemsToImport.count) New")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.itemsToImport.isEmpty)

                }
            }
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    /// "12.3 MB/s · 2 min left"
    static func rate(_ bytesPerSecond: Double, remaining: TimeInterval?) -> String {
        let speed = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
        guard let remaining else { return speed }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : remaining >= 60 ? [.minute] : [.second]
        let left = formatter.string(from: max(remaining, 1)) ?? ""
        return String(localized: "\(speed) · \(left) left")
    }

    @ViewBuilder private var status: some View {
        if let summary = model.importSummary {
            HStack(spacing: 8) {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                switch model.lastImportLocation {
                case .photos?:
                    Button("Open Photos") { model.showLastImport() }.buttonStyle(.link)
                case .folder?:
                    Button("Show in Finder") { model.showLastImport() }.buttonStyle(.link)
                case nil:
                    EmptyView()
                }
            }
        } else if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else if model.isListing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading card…").foregroundStyle(.secondary)
            }
        } else if let battery = model.batteryPercent, battery < 20 {
            Label("Camera battery low: \(battery)%", systemImage: "battery.25percent")
                .foregroundStyle(.orange)
        }
    }
}
