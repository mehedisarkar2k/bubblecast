import AppKit
import SwiftUI

@MainActor
final class LibraryWindow {
    private var window: NSWindow?
    let library = RecordingLibrary()

    func show() {
        library.refresh()
        library.checkDrive()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Bubblecast Library"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 720, height: 460)
            window.contentView = NSHostingView(rootView: LibraryView(library: library, auth: library.auth))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All Recordings", today = "Today", week = "This Week", drive = "On Drive", shared = "Shared"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .all: "film.stack"
        case .today: "sun.max"
        case .week: "calendar"
        case .drive: "icloud"
        case .shared: "link"
        }
    }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest", oldest = "Oldest", largest = "Largest", longest = "Longest"
    var id: Self { self }
}

private struct LibraryView: View {
    @ObservedObject var library: RecordingLibrary
    @ObservedObject var auth: GoogleAuth
    @State private var filter: LibraryFilter? = .all
    @State private var sort = LibrarySort.newest
    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var renaming: Recording?
    @State private var newName = ""
    @State private var deleting: [Recording] = []

    var body: some View {
        NavigationSplitView {
            List(LibraryFilter.allCases, selection: $filter) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                content
                Divider()
                footer
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Search recordings")
            .toolbar { toolbar }
        }
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let renaming { library.rename(renaming, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete from this Mac and from Google Drive?",
                            isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } })) {
            Button("Delete Everywhere", role: .destructive) { library.deleteEverywhere(deleting) }
        } message: {
            Text("The local file goes to the Trash. The Drive copy is deleted and its link stops working.")
        }
        .alert("Bubblecast", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if visible.isEmpty {
            ContentUnavailableView(search.isEmpty ? "No recordings yet" : "No matches",
                                   systemImage: "film.stack",
                                   description: Text(search.isEmpty ? "Recordings appear here after you press Stop." : "Try another search."))
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(visible) { recording in
                        RecordingCard(recording: recording, library: library, selected: selection.contains(recording.id),
                                      rename: { newName = recording.title; renaming = recording },
                                      deleteEverywhere: { deleting = [recording] })
                            .onTapGesture(count: 2) { library.play(recording) }
                            .onTapGesture { select(recording) }
                    }
                }
                .padding(16)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(library.storageSummary).font(.callout).foregroundStyle(.secondary)
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count) selected").font(.callout)
                if auth.isConnected {
                    Button("Upload") { selected.forEach { library.upload($0) } }
                }
                Button("Move to Trash") {
                    library.moveToTrash(selected)
                    selection.removeAll()
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("Sort", selection: $sort) {
                ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            if auth.isConnected {
                Menu {
                    Toggle("Upload new recordings automatically", isOn: $library.autoUpload)
                    Button("Check Drive now") { library.checkDrive() }
                    Divider()
                    Button("Disconnect Google Drive") { library.disconnectDrive() }
                } label: {
                    Label("Google Drive", systemImage: "checkmark.icloud")
                }
            } else {
                Button { library.connectDrive() } label: {
                    Label("Connect Google Drive", systemImage: "icloud.and.arrow.up")
                }
                .help(auth.isConfigured ? "Sign in once to upload and share recordings" : "Choose your Google client file, then sign in once")
            }
        }
        ToolbarItem {
            Button { library.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        }
    }

    private var selected: [Recording] { library.recordings.filter { selection.contains($0.id) } }

    private var visible: [Recording] {
        let calendar = Calendar.current
        let matching = library.recordings.filter { recording in
            let status = library.status(of: recording)
            switch filter ?? .all {
            case .all: break
            case .today: guard calendar.isDateInToday(recording.date) else { return false }
            case .week: guard calendar.isDate(recording.date, equalTo: Date(), toGranularity: .weekOfYear) else { return false }
            case .drive: guard [.onDrive, .shared, .outdated].contains(status) else { return false }
            case .shared: guard status == .shared else { return false }
            }
            return search.isEmpty || recording.title.localizedCaseInsensitiveContains(search)
        }
        switch sort {
        case .newest: return matching.sorted { $0.date > $1.date }
        case .oldest: return matching.sorted { $0.date < $1.date }
        case .largest: return matching.sorted { $0.size > $1.size }
        case .longest: return matching.sorted { (library.durations[$0.id] ?? 0) > (library.durations[$1.id] ?? 0) }
        }
    }

    private func select(_ recording: Recording) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(recording.id) { selection.remove(recording.id) } else { selection.insert(recording.id) }
        } else {
            selection = [recording.id]
        }
    }
}
