import SwiftUI

struct RecordingCard: View {
    let recording: Recording
    @ObservedObject var library: RecordingLibrary
    let selected: Bool
    let rename: () -> Void
    let deleteEverywhere: () -> Void

    var body: some View {
        let status = library.status(of: recording)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                badge(status).padding(6)
            }
            Text(recording.title).font(.headline).lineLimit(1)
            Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .contextMenu { actions(status) }
    }

    private var thumbnail: some View {
        Group {
            if let image = library.thumbnails[recording.id] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary).overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func badge(_ status: CloudStatus) -> some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var details: String {
        var parts = [recording.date.formatted(date: .abbreviated, time: .shortened)]
        if let seconds = library.durations[recording.id], seconds.isFinite {
            parts.append(String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: recording.size, countStyle: .file))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    func actions(_ status: CloudStatus) -> some View {
        Button("Play") { library.play(recording) }
        Button("Rename…", action: rename)
        Button("Show in Finder") { library.showInFinder(recording) }
        Divider()
        if library.auth.isConnected {
            switch status {
            case .local, .missing, .waiting:
                Button("Upload to Drive") { library.upload(recording) }
                Button("Upload & Copy Link") { library.copyLink(recording) }
            case .uploading:
                EmptyView()
            case .onDrive, .shared, .outdated:
                Button(status == .shared ? "Copy Link" : "Share & Copy Link") { library.copyLink(recording) }
                if status == .shared { Button("Stop Sharing") { library.stopSharing(recording) } }
                if status == .outdated { Button("Update on Drive") { library.upload(recording) } }
                Button("Remove from Drive") { library.removeFromDrive(recording) }
            }
        } else {
            Button("Connect Google Drive…") { library.connectDrive() }
        }
        Divider()
        Button("Move to Trash") { library.moveToTrash([recording]) }
        if status != .local { Button("Delete Everywhere…", action: deleteEverywhere) }
    }
}
