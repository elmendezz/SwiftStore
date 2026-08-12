import Foundation
import Combine

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadQueue: [AltStoreApp] = []

    private let fileManager: AppFileManager
    
    private var currentDownload: AltStoreApp?
    private var downloadSession: URLSession!
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var taskAppMap: [Int: AltStoreApp] = [:]

    init(fileManager: AppFileManager) {
        self.fileManager = fileManager
        super.init()
        let appConfig = URLSessionConfiguration.default
        appConfig.timeoutIntervalForRequest = 60.0
        self.downloadSession = URLSession(configuration: appConfig, delegate: self, delegateQueue: nil)
    }

    func startDownload(app: AltStoreApp) {
        if fileManager.downloadedApps.contains(app.bundleIdentifier) || downloadQueue.contains(app) || currentDownload == app { return }
        downloadQueue.append(app)
        processDownloadQueue()
    }

    func processDownloadQueue() {
        guard currentDownload == nil, let nextApp = downloadQueue.first else { return }
        currentDownload = nextApp
        downloadQueue.removeFirst()
        
        guard let url = URL(string: nextApp.downloadURL) else {
            finishDownloadProcessing(for: nextApp.bundleIdentifier)
            return
        }
        
        let task = downloadSession.downloadTask(with: url)
        downloadTasks[nextApp.bundleIdentifier] = task
        taskAppMap[task.taskIdentifier] = nextApp
        
        DispatchQueue.main.async {
            self.isDownloading[nextApp.bundleIdentifier] = true
            self.downloadProgress[nextApp.bundleIdentifier] = 0.01
        }
        
        task.resume()
    }

    func cancelDownload(app: AltStoreApp) {
        if let index = downloadQueue.firstIndex(of: app) {
            downloadQueue.remove(at: index)
        } else if currentDownload == app {
            downloadTasks[app.bundleIdentifier]?.cancel()
            // The error delegate method will handle cleanup.
        }
    }

    private func finishDownloadProcessing(for identifier: String) {
        DispatchQueue.main.async {
            self.isDownloading[identifier] = false
            self.downloadProgress[identifier] = 0.0
            self.downloadTasks[identifier] = nil
            if self.currentDownload?.bundleIdentifier == identifier {
                self.currentDownload = nil
                self.processDownloadQueue()
            }
        }
    }
    
    // MARK: - URLSessionDownloadDelegate (App Downloads)
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let app = taskAppMap[downloadTask.taskIdentifier] else { return }
        
        let dest = fileManager.downloadsDirectory.appendingPathComponent("\(app.bundleIdentifier).ipa")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
        
        DispatchQueue.main.async {
            self.fileManager.downloadedApps.insert(app.bundleIdentifier)
            self.fileManager.refreshFilesList()
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let app = taskAppMap[task.taskIdentifier] {
            // This gets called on success (error == nil), cancellation, or network error.
            // It's the single point of cleanup for a task.
            finishDownloadProcessing(for: app.bundleIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let app = taskAppMap[downloadTask.taskIdentifier], totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async { self.downloadProgress[app.bundleIdentifier] = progress }
        }
    }
}