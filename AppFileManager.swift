import Foundation
import Combine

class AppFileManager: ObservableObject {
    @Published var downloadedFiles: [URL] = []
    @Published var downloadedApps: Set<String> = []
    @Published var downloadFolder: String {
        didSet {
            // When the folder changes, refresh the lists.
            refreshFilesList()
            checkDownloadedFiles()
        }
    }

    var downloadsDirectory: URL {
        let directory: FileManager.SearchPathDirectory = downloadFolder == "Documentos" ? .documentDirectory : .cachesDirectory
        guard let url = FileManager.default.urls(for: directory, in: .userDomainMask).first else {
            // This should not happen on a real device.
            fatalError("Could not find the user's directory.")
        }
        return url
    }

    init(initialDownloadFolder: String) {
        self.downloadFolder = initialDownloadFolder
        refreshFilesList()
        checkDownloadedFiles()
    }

    func refreshFilesList() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey])
            DispatchQueue.main.async {
                self.downloadedFiles = files.filter { $0.pathExtension == "ipa" }
            }
        } catch {
            DispatchQueue.main.async { self.downloadedFiles = [] }
        }
    }

    func checkDownloadedFiles() {
        var existing: Set<String> = []
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path)
            for file in files where file.hasSuffix(".ipa") {
                existing.insert(file.replacingOccurrences(of: ".ipa", with: ""))
            }
        } catch { /* Directory might not exist yet, which is fine. */ }
        DispatchQueue.main.async { self.downloadedApps = existing }
    }

    func deleteAppFile(app: AltStoreApp) {
        let fileURL = downloadsDirectory.appendingPathComponent("\(app.bundleIdentifier).ipa")
        try? FileManager.default.removeItem(at: fileURL)
        checkDownloadedFiles()
        refreshFilesList()
    }
}