import AppKit
import Darwin
import KeyboardShortcuts
import Observation
import UniformTypeIdentifiers

enum PadFormat: String, CaseIterable, Identifiable {
    case txt, md

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum PadReuse: Int, CaseIterable, Identifiable {
    case alwaysNew = 0, fiveMinutes = 5, tenMinutes = 10, fifteenMinutes = 15, thirtyMinutes = 30, oneHour = 60

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .alwaysNew: "Always new"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        }
    }
}

enum PadError: LocalizedError {
    case unsupported
    case encoding
    case changed
    case missingFolder
    case invalidName
    case nameExists
    case renamePermission

    var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a .txt or .md file."
        case .encoding: "This file is not UTF-8 text. It was not changed."
        case .changed: "The file changed outside Pad. Use Save As to keep both versions."
        case .missingFolder: "The chosen folder is unavailable. Select it again in Files settings."
        case .invalidName: "Enter a filename without slashes, colons, or control characters. The name cannot be empty, . or .., or longer than 255 bytes including its extension."
        case .nameExists: "A file with that name already exists. Choose another name."
        case .renamePermission: "Pad cannot rename this file in its folder. Use Save As to choose a new name and keep the original."
        }
    }
}

@MainActor
@Observable
final class PadDocument {
    var floating: Bool {
        didSet {
            defaults.set(floating, forKey: Self.floatingKey)
            panel?.level = floating ? .floating : .normal
        }
    }
    var format: PadFormat {
        didSet {
            defaults.set(format.rawValue, forKey: Self.formatKey)
            updateTitle()
        }
    }
    var saveAutomatically: Bool {
        didSet { defaults.set(saveAutomatically, forKey: Self.autoSaveKey) }
    }
    var reusePeriod: PadReuse {
        didSet { defaults.set(reusePeriod.rawValue, forKey: Self.reuseKey) }
    }
    var nameParts: [PadNamePart] {
        didSet {
            if let data = try? JSONEncoder().encode(nameParts) { defaults.set(data, forKey: Self.namePartsKey) }
        }
    }
    private(set) var folder: URL
    private(set) var url: URL?
    private(set) var documentID = UUID()
    var text = ""
    private(set) var savedText = ""
    var isActive = false
    var settingsPresented = false
    var showSettings: @MainActor () -> Void = {}
    var error: String?
    private(set) var notice: String? {
        didSet {
            noticeTask?.cancel()
            noticeGeneration += 1
            guard notice != nil else { return }
            let generation = noticeGeneration
            let duration = noticeDuration
            noticeTask = Task { [weak self] in
                do { try await Task.sleep(for: duration) } catch { return }
                guard let self, generation == self.noticeGeneration else { return }
                self.notice = nil
            }
        }
    }
    private var noticeTask: Task<Void, Never>?
    private var noticeGeneration = 0
    private let noticeDuration: Duration
    private var baseline: Data?
    private var documentScope: URL?
    private var folderScope: URL?
    private var panel: PadPanel?
    private var createdAt: Date?
    private var openedFromDisk = false
    private var pendingName: String?
    private var nextNumber: Int
    private enum Operation { case transition, filePanel, sharing }
    private var operation: Operation?
    private var sharePicker: NSSharingServicePicker?
    private var shareDelegate: PadSharePickerDelegate?
    private let defaults: UserDefaults
    private let presentsWindow: Bool
    private let copyPath: @MainActor (String) -> Void
    private let selectOpenFile: @MainActor () async -> URL?
    private let selectSaveFile: @MainActor (URL, String) async -> URL?
    private let discardChanges: @MainActor () -> Bool

    private static let floatingKey = "pad.floating"
    private static let formatKey = "pad.format"
    private static let folderBookmarkKey = "pad.folderBookmark"
    private static let autoSaveKey = "pad.saveAutomatically"
    private static let reuseKey = "pad.reusePeriod"
    private static let namePartsKey = "pad.nameParts"
    private static let nextNumberKey = "pad.nextNumber"

    private static var downloadsFolder: URL {
        // FileManager's Downloads URL is redirected into a sandbox container even with Downloads access.
        guard let record = getpwuid(getuid()), let home = String(validatingCString: record.pointee.pw_dir) else {
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        return URL(fileURLWithPath: home, isDirectory: true).appending(path: "Downloads", directoryHint: .isDirectory)
    }

    init(defaults: UserDefaults = .standard,
         defaultFolder: URL? = nil, presentsWindow: Bool = true,
         noticeDuration: Duration = .seconds(2),
         copyPath: @escaping @MainActor (String) -> Void = {
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString($0, forType: .string)
         },
         selectOpenFile: (@MainActor () async -> URL?)? = nil,
         selectSaveFile: (@MainActor (URL, String) async -> URL?)? = nil,
         discardChanges: (@MainActor () -> Bool)? = nil) {
        self.noticeDuration = noticeDuration
        self.defaults = defaults
        self.presentsWindow = presentsWindow
        self.copyPath = copyPath
        self.selectOpenFile = selectOpenFile ?? Self.presentOpenPanel
        self.selectSaveFile = selectSaveFile ?? Self.presentSavePanel
        self.discardChanges = discardChanges ?? Self.confirmDiscard
        #if DEBUG
        let defaultFloating = false
        #else
        let defaultFloating = true
        #endif
        floating = defaults.object(forKey: Self.floatingKey) == nil ? defaultFloating : defaults.bool(forKey: Self.floatingKey)
        format = defaults.string(forKey: Self.formatKey).flatMap(PadFormat.init(rawValue:)) ?? .txt
        saveAutomatically = defaults.object(forKey: Self.autoSaveKey) == nil ? true : defaults.bool(forKey: Self.autoSaveKey)
        reusePeriod = PadReuse(rawValue: defaults.object(forKey: Self.reuseKey) as? Int ?? 15) ?? .fifteenMinutes
        nameParts = defaults.data(forKey: Self.namePartsKey)
            .flatMap { try? JSONDecoder().decode([PadNamePart].self, from: $0) } ?? PadFilename.defaultParts
        nextNumber = max(1, defaults.integer(forKey: Self.nextNumberKey))
        folder = defaultFolder ?? Self.downloadsFolder
        var stale = false
        if let data = defaults.data(forKey: Self.folderBookmarkKey),
           let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
            folder = resolved
            folderScope = resolved.startAccessingSecurityScopedResource() ? resolved : nil
        }
    }

    var isDirty: Bool { text != savedText }
    var isBusy: Bool { operation != nil }
    var isVisible: Bool { panel?.isVisible == true }
    var isDefaultFolder: Bool { defaults.data(forKey: Self.folderBookmarkKey) == nil }
    var editableName: String { url?.deletingPathExtension().lastPathComponent ?? pendingName ?? "" }
    var displayName: String {
        url?.lastPathComponent ?? pendingName.map { "\($0).\(format.rawValue)" } ?? "Untitled"
    }
    var namePreview: String {
        (try? PadFilename.name(parts: nameParts, format: format, number: nextNumber)) ?? "Invalid filename"
    }

    func installShortcut() {
        KeyboardShortcuts.onKeyDown(for: .pad) { [weak self] in self?.toggle() }
    }

    func chooseFolder() async {
        guard !isBusy else { return }
        operation = .filePanel
        defer { operation = nil }
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = true
        picker.prompt = "Use Folder"
        picker.directoryURL = folder
        guard await picker.begin() == .OK, let chosen = picker.url else { return }
        do {
            let data = try chosen.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            folderScope?.stopAccessingSecurityScopedResource()
            defaults.set(data, forKey: Self.folderBookmarkKey)
            folder = chosen
            folderScope = chosen.startAccessingSecurityScopedResource() ? chosen : nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func useDownloads() {
        guard !isBusy else { return }
        folderScope?.stopAccessingSecurityScopedResource()
        folderScope = nil
        defaults.removeObject(forKey: Self.folderBookmarkKey)
        folder = Self.downloadsFolder
        error = nil
    }

    func newFile(now: Date = .now) {
        guard !isBusy else { return }
        operation = .transition
        defer { operation = nil }
        guard finishCurrent() else { return }
        resetDocument()
        createdAt = now
        show()
    }

    func toggle(now: Date = .now) {
        guard !isBusy else { return }
        if isVisible {
            close()
        } else if openedFromDisk || isReusable(at: now) {
            refreshCurrentFile()
            show()
        } else {
            newFile(now: now)
        }
    }

    func showCurrent(now: Date = .now) {
        guard !isBusy else { return }
        if isVisible {
            show()
        } else {
            toggle(now: now)
        }
    }

    func commandNew(now: Date = .now) {
        newFile(now: now)
    }

    private func isReusable(at now: Date) -> Bool {
        guard let createdAt, !openedFromDisk, reusePeriod != .alwaysNew else { return false }
        return now.timeIntervalSince(createdAt) < TimeInterval(reusePeriod.rawValue * 60)
    }

    private func resetDocument() {
        documentID = UUID()
        documentScope?.stopAccessingSecurityScopedResource()
        documentScope = nil
        url = nil
        baseline = nil
        text = ""
        savedText = ""
        error = nil
        notice = nil
        createdAt = nil
        openedFromDisk = false
        pendingName = nil
    }

    func openPicker() async {
        guard !isBusy else { return }
        operation = .filePanel
        defer { operation = nil }
        guard let chosen = await selectOpenFile() else { return }
        openDocument(chosen)
    }

    private static func presentOpenPanel() async -> URL? {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        picker.allowsOtherFileTypes = false
        guard await picker.begin() == .OK else { return nil }
        return picker.url
    }

    func open(_ file: URL) {
        guard !isBusy else { return }
        operation = .transition
        defer { operation = nil }
        openDocument(file)
    }

    private func openDocument(_ file: URL) {
        guard ["txt", "md"].contains(file.pathExtension.lowercased()) else {
            error = PadError.unsupported.localizedDescription
            show()
            return
        }
        if file.standardizedFileURL == url?.standardizedFileURL {
            refreshCurrentFile()
            show()
            return
        }
        let accessing = file.startAccessingSecurityScopedResource()
        do {
            let bytes = try Data(contentsOf: file)
            guard let content = String(data: bytes, encoding: .utf8) else { throw PadError.encoding }
            guard finishCurrent() else {
                if accessing { file.stopAccessingSecurityScopedResource() }
                return
            }
            documentScope?.stopAccessingSecurityScopedResource()
            documentScope = accessing ? file : nil
            documentID = UUID()
            url = file
            text = content
            savedText = content
            baseline = bytes
            createdAt = nil
            openedFromDisk = true
            pendingName = nil
            error = nil
            notice = nil
            show()
        } catch {
            if accessing { file.stopAccessingSecurityScopedResource() }
            self.error = error.localizedDescription
            show()
        }
    }

    private func refreshCurrentFile() {
        guard let url else { return }
        do {
            let bytes = try Data(contentsOf: url)
            guard let content = String(data: bytes, encoding: .utf8) else { throw PadError.encoding }
            if isDirty {
                guard bytes == baseline else { throw PadError.changed }
            } else {
                text = content
                savedText = content
                baseline = bytes
                notice = nil
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
            notice = nil
        }
    }

    func save() {
        guard !isBusy else { return }
        saveCurrent()
    }

    private func saveCurrent() {
        do {
            if let url {
                guard try Data(contentsOf: url) == baseline else { throw PadError.changed }
                let bytes = Data(text.utf8)
                try bytes.write(to: url, options: .atomic)
                baseline = bytes
                savedText = text
                notice = "Saved"
            } else {
                guard isDefaultFolder || folderScope != nil else { throw PadError.missingFolder }
                let bytes = Data(text.utf8)
                let destination: URL
                if let pendingName {
                    destination = folder.appending(path: try PadFilename.filename(stem: pendingName, extension: format.rawValue))
                    guard !FileManager.default.fileExists(atPath: destination.path) else { throw PadError.nameExists }
                    try bytes.write(to: destination, options: .withoutOverwriting)
                } else {
                    destination = try saveGeneratedFile(bytes)
                }
                url = destination
                pendingName = nil
                baseline = bytes
                savedText = text
                if !isDefaultFolder {
                    documentScope = folder.startAccessingSecurityScopedResource() ? folder : nil
                }
                copyPath(destination.path)
                notice = "Saved. Path copied."
            }
            error = nil
            updateTitle()
        } catch { self.error = error.localizedDescription; notice = nil }
    }

    func saveAs() async {
        guard !isBusy else { return }
        operation = .filePanel
        defer { operation = nil }
        let content = text
        let directory = url?.deletingLastPathComponent() ?? folder
        let suggestion: (name: String, number: Int?)
        do {
            if let url { suggestion = (url.lastPathComponent, nil) }
            else if let pendingName {
                suggestion = (try PadFilename.filename(stem: pendingName, extension: format.rawValue), nil)
            } else {
                let generated = try PadFilename.available(in: directory, parts: nameParts,
                                                             format: format, number: nextNumber)
                guard generated.number < Int.max else { throw PadError.invalidName }
                suggestion = (generated.url.lastPathComponent, generated.number)
            }
        } catch {
            self.error = error.localizedDescription
            notice = nil
            return
        }
        guard let destination = await selectSaveFile(directory, suggestion.name) else { return }
        let accessing = destination.startAccessingSecurityScopedResource()
        do {
            if destination.standardizedFileURL == url?.standardizedFileURL,
               try Data(contentsOf: destination) != baseline {
                throw PadError.changed
            }
            let bytes = Data(content.utf8)
            try bytes.write(to: destination, options: .atomic)
            documentScope?.stopAccessingSecurityScopedResource()
            documentScope = accessing ? destination : nil
            url = destination
            pendingName = nil
            baseline = bytes
            savedText = content
            if let number = suggestion.number, destination.lastPathComponent == suggestion.name {
                advanceGeneratedNumber(after: number)
            }
            error = nil
            notice = "Saved"
            updateTitle()
        } catch {
            if accessing { destination.stopAccessingSecurityScopedResource() }
            self.error = error.localizedDescription
            notice = nil
        }
    }

    private static func presentSavePanel(directory: URL, name: String) async -> URL? {
        let picker = NSSavePanel()
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        picker.directoryURL = directory
        picker.nameFieldStringValue = name
        guard await picker.begin() == .OK else { return nil }
        return picker.url
    }

    func share(from anchor: NSView? = nil) {
        guard !isBusy, let view = anchor ?? panel?.contentView else { return }
        operation = .sharing
        do {
            let picker = NSSharingServicePicker(items: [try shareableURL()])
            let delegate = PadSharePickerDelegate { [weak self] in
                self?.operation = nil
                self?.sharePicker = nil
                self?.shareDelegate = nil
                if self?.panel?.isKeyWindow == false { self?.lostFocus() }
            }
            picker.delegate = delegate
            sharePicker = picker
            shareDelegate = delegate
            let rect = anchor == nil
                ? NSRect(x: view.bounds.maxX - 90, y: view.bounds.maxY - 38, width: 32, height: 24)
                : view.bounds
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
            error = nil
        } catch {
            operation = nil
            self.error = error.localizedDescription
        }
    }

    func shareableURL(in temporaryFolder: URL = FileManager.default.temporaryDirectory) throws -> URL {
        if let url, !isDirty, let current = try? Data(contentsOf: url), current == baseline { return url }
        let directory = temporaryFolder.appending(path: "PadShare-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name: String
        if let url { name = url.lastPathComponent }
        else if let pendingName { name = "\(pendingName).\(format.rawValue)" }
        else { name = try PadFilename.name(parts: nameParts, format: format, number: nextNumber) }
        let snapshot = directory.appending(path: name)
        try Data(text.utf8).write(to: snapshot, options: .atomic)
        return snapshot
    }

    func close() {
        guard !isBusy else { return }
        operation = .transition
        defer { operation = nil }
        guard finishCurrent() else { return }
        isActive = false
        panel?.orderOut(nil)
    }

    func lostFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isBusy, !self.settingsPresented,
                  self.panel?.isVisible == true, self.panel?.isKeyWindow == false else { return }
            self.close()
        }
    }

    private func finishCurrent() -> Bool {
        guard isDirty else { return true }
        if saveAutomatically {
            saveCurrent()
            return !isDirty
        }
        if url != nil {
            guard discardChanges() else { return false }
        }
        if url == nil { resetDocument() }
        else { text = savedText }
        return true
    }

    func canTerminate() -> Bool {
        guard !isBusy else { return false }
        operation = .transition
        defer { operation = nil }
        return finishCurrent()
    }

    func expand() { panel?.toggleExpanded() }

    @discardableResult
    func rename(to input: String) -> Bool {
        guard !isBusy else { return false }
        operation = .transition
        defer { operation = nil }
        do {
            let fileExtension = url?.pathExtension ?? format.rawValue
            let stem = try PadFilename.validatedStem(input)
            let name = try PadFilename.filename(stem: stem, extension: fileExtension)
            if let source = url {
                let destination = source.deletingLastPathComponent().appending(path: name)
                if destination != source {
                    guard canRenameInContainingFolder(source) else { throw PadError.renamePermission }
                    guard try Data(contentsOf: source) == baseline else { throw PadError.changed }
                    // Exclusive rename prevents an existing destination from being replaced, including races.
                    let result = source.withUnsafeFileSystemRepresentation { sourcePath in
                        destination.withUnsafeFileSystemRepresentation { destinationPath in
                            renameatx_np(AT_FDCWD, sourcePath!, AT_FDCWD, destinationPath!, UInt32(RENAME_EXCL))
                        }
                    }
                    guard result == 0 else {
                        switch errno {
                        case EEXIST: throw PadError.nameExists
                        case EACCES, EPERM: throw PadError.renamePermission
                        default: throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                        }
                    }
                    url = destination
                    if documentScope?.standardizedFileURL == source.standardizedFileURL {
                        documentScope?.stopAccessingSecurityScopedResource()
                        documentScope = nil
                    }
                }
            } else {
                pendingName = stem
            }
            error = nil
            notice = "Renamed"
            updateTitle()
            return true
        } catch {
            self.error = error.localizedDescription
            notice = nil
            return false
        }
    }

    private func canRenameInContainingFolder(_ source: URL) -> Bool {
        guard documentScope?.standardizedFileURL == source.standardizedFileURL else { return true }
        // A grant for one file does not authorize its new sibling name. Save As can request that grant.
        let directory = source.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
        let authorizedFolders = [Self.downloadsFolder, FileManager.default.temporaryDirectory] + [folderScope].compactMap { $0 }
        return authorizedFolders.contains { directory.starts(with: $0.resolvingSymlinksInPath().pathComponents) }
    }

    private func saveGeneratedFile(_ bytes: Data) throws -> URL {
        let now = Date.now
        while true {
            let candidate = try PadFilename.available(in: folder, parts: nameParts, format: format,
                                                         now: now, number: nextNumber)
            guard candidate.number < Int.max else { throw PadError.invalidName }
            do {
                try bytes.write(to: candidate.url, options: .withoutOverwriting)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
            advanceGeneratedNumber(after: candidate.number)
            return candidate.url
        }
    }

    private func advanceGeneratedNumber(after number: Int) {
        nextNumber = max(number + 1, max(nextNumber, defaults.integer(forKey: Self.nextNumberKey)))
        defaults.set(nextNumber, forKey: Self.nextNumberKey)
    }

    private func updateTitle() {
        panel?.title = "Pad: \(displayName)"
    }

    private func show() {
        guard presentsWindow else { return }
        if panel == nil { panel = PadPanel(files: self) }
        updateTitle()
        // PadPanel.becomeKey owns activation; focus cannot succeed before the window is key.
        panel?.makeKeyAndOrderFront(nil)
    }

    private static func confirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "Your changes to this text file have not been saved."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

private final class PadSharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onDismiss()
    }
}
