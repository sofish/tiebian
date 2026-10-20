import Darwin
import Foundation

/// Watches the folder rather than the file so an atomic replacement (the way
/// the app and the CLI both save) is still observed.
@MainActor
final class NotesFileWatcher {
    private let fileURL: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var pending: DispatchWorkItem?

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        start()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    private func start() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("EdgePeek: could not watch notes directory at \(directory.path)")
            return
        }

        let watchedDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchedDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleReload()
            }
        }
        source.setCancelHandler {
            close(watchedDescriptor)
        }
        self.source = source
        source.resume()
    }

    private func scheduleReload() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.onChange()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }
}
