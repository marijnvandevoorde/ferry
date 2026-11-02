import SwiftUI

struct GalleryView: View {
    @Environment(CameraModel.self) private var model
    @State private var filter = Filter.all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", new = "Not Imported"
        var id: String { rawValue }
    }

    private var visibleItems: [PhotoItem] {
        filter == .new ? model.newItems : model.items
    }

    private var sections: [(day: Date, items: [PhotoItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visibleItems) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            if visibleItems.isEmpty && !model.isListing {
                ContentUnavailableView(filter == .new ? "Everything is imported" : "No photos on the card",
                                       systemImage: filter == .new ? "checkmark.circle" : "photo.on.rectangle.angled")
                    .padding(.top, 120)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)], spacing: 10,
                      pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.day) { section in
                    Section {
                        ForEach(section.items) { item in
                            PhotoCell(item: item, isSelected: model.selection.contains(item.id))
                                .onTapGesture { toggle(item) }
                        }
                    } header: {
                        SectionHeader(day: section.day, items: section.items)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ImportBar()
        }
        .navigationTitle(model.cameraName.isEmpty ? "Camera" : model.cameraName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItemGroup {
                Menu {
                    Button("Select All") { model.selection = Set(visibleItems.map(\.id)) }
                        .keyboardShortcut("a")
                    Button("Select Not Imported") { model.selection = Set(model.newItems.map(\.id)) }
                    Button("Deselect All") { model.selection = [] }
                        .keyboardShortcut("d")
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
            return "Reading card… \(model.listProgress.loaded) of \(model.listProgress.total)"
        }
        let n = model.items.count
        let new = model.newItems.count
        return "\(n) \(n == 1 ? "item" : "items") · \(new) not imported"
    }

    private func toggle(_ item: PhotoItem) {
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
        if day == Calendar.current.startOfDay(for: .distantPast) { return "Unknown date" }
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
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
                        Text("Importing \(p.filename) — \(p.index) of \(p.total)")
                            .font(.callout)
                            .lineLimit(1)
                        ProgressView(value: (Double(p.index - 1) + p.fraction) / Double(max(p.total, 1)))
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
                        Text(model.newItems.isEmpty ? "No New Items" : "Import \(model.newItems.count) New")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.newItems.isEmpty || model.isListing)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    @ViewBuilder private var status: some View {
        if let summary = model.importSummary {
            HStack(spacing: 8) {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Button("Open Photos") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
                }
                .buttonStyle(.link)
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
        }
    }
}
