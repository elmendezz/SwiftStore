import Foundation
import Combine

class SourceManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var sources: [AltStoreSource] = [] { didSet { saveSources() } }
    @Published var apps: [AltStoreApp] = []
    
    @Published var isUpdatingRepos: Bool = false
    @Published var repoUpdateStatus: String = ""
    @Published var repoDownloadProgress: Double = 0.0
    @Published var activityLog: [String] = []
    
    @Published var recentlyDeletedSources: [AltStoreSource] = []
    @Published var showUndoAlert: Bool = false
    @Published var showSourceExistsAlert: Bool = false
    
    private var repoDownloadSession: URLSession!
    private var repoDownloadTaskIdentifier: Int?
    private var repoDownloadURL: String?
    
    override init() {
        super.init()
        let repoConfig = URLSessionConfiguration.default
        repoConfig.timeoutIntervalForResource = 10.0 // Timeout for the entire download
        self.repoDownloadSession = URLSession(configuration: repoConfig, delegate: self, delegateQueue: nil)
        
        loadSources()
        fetchApps()
    }
    
    // MARK: - Persistence
    func saveSources() {
        if let encoded = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(encoded, forKey: "savedSources")
        }
    }
    
    func loadSources() {
        if let data = UserDefaults.standard.data(forKey: "savedSources"),
           let decoded = try? JSONDecoder().decode([AltStoreSource].self, from: data) {
            sources = decoded
        } else {
            // Default source
            sources = [AltStoreSource(name: "AltStore Official", url: "https://apps.altstore.io", iconURL: "https://altstore.io/altstore-icon.png", isActive: true)]
        }
    }
    
    // MARK: - Network Functions
    func addSource(url: String) {
        guard let validURL = URL(string: url) else {
            finishUpdatingRepos(message: "Error: La URL no parece ser válida.", delay: 3.5)
            return
        }
        
        DispatchQueue.main.async {
            self.activityLog.removeAll()
            self.log("▶️ Iniciando adición de fuente: \(url)")
            self.isUpdatingRepos = true
            self.repoUpdateStatus = "Descargando JSON del nuevo repositorio..."
            self.repoDownloadProgress = 0.01
        }
        
        log("⬇️ Creando tarea de descarga con timeout de recurso de 10s.")
        self.repoDownloadURL = url
        let task = repoDownloadSession.downloadTask(with: validURL)
        self.repoDownloadTaskIdentifier = task.taskIdentifier
        task.resume()
    }

    func fetchApps() {
        let activeSources = sources.filter { $0.isActive }
        if activeSources.isEmpty {
            apps.removeAll()
            return
        }
        
        DispatchQueue.main.async {
            self.activityLog.removeAll()
            self.log("🔄 Iniciando sincronización de \(activeSources.count) fuentes activas.")
            self.isUpdatingRepos = true
            self.repoUpdateStatus = "Sincronizando \(activeSources.count) fuentes..."
        }
        
        let syncConfig = URLSessionConfiguration.default
        syncConfig.timeoutIntervalForRequest = 30.0
        let syncSession = URLSession(configuration: syncConfig)
        
        let group = DispatchGroup()
        var allNewApps: [AltStoreApp] = []
        let appProcessingQueue = DispatchQueue(label: "com.swiftstore.app-processing", qos: .userInitiated)
        
        for source in activeSources {
            guard let url = URL(string: source.url) else { continue }
            group.enter()
            
            syncSession.dataTask(with: url) { [weak self] data, response, error in
                defer { group.leave() }
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        let msg = "Error en \(source.name): \(error.localizedDescription)"
                        self.repoUpdateStatus = msg; self.log("⚠️ \(msg)")
                    }
                    return
                }
                
                if let data = data {
                    do {
                        let feed = try JSONDecoder().decode(AltStoreFeed.self, from: data)
                        DispatchQueue.main.async {
                            let msg = "Procesando apps de: \(feed.name ?? source.name)"
                            self.repoUpdateStatus = msg; self.log("⚙️ \(msg)")
                        }
                        appProcessingQueue.sync {
                            allNewApps.append(contentsOf: feed.apps)
                        }
                    } catch {
                        DispatchQueue.main.async { self.repoUpdateStatus = "JSON corrupto en: \(source.name)" }
                        self.log("🛑 Error de decodificación en \(source.name).")
                    }
                }
            }.resume()
        }
        
        group.notify(queue: appProcessingQueue) { // Realizar el procesamiento final en el hilo de fondo
            let uniqueApps = Array(Set(allNewApps)) // Eliminar duplicados
            let sortedApps = uniqueApps.sorted { $0.name < $1.name } // Ordenar alfabéticamente
            
            // Volver al hilo principal solo para actualizar la UI
            DispatchQueue.main.async {
                self.apps = sortedApps
                let msg = "Sincronización Completada"
                self.log("✅ \(msg): \(sortedApps.count) apps únicas cargadas."); self.finishUpdatingRepos(message: msg)
            }
        }
    }
    
    private func processDownloadedRepo(url: String, data: Data?, error: Error?) {
        if let error = error {
            let errorMessage: String
            if let urlError = error as? URLError {
                errorMessage = urlError.code == .timedOut ? "Error: La solicitud tardó más de 10 segundos (timeout)." : "Fallo de red: \(error.localizedDescription)"
            } else {
                errorMessage = "Error inesperado: \(error.localizedDescription)"
            }
            log("🛑 \(errorMessage)")
            finishUpdatingRepos(message: errorMessage, delay: 3.5)
            return
        }
        
        guard let data = data else {
            log("🛑 Error: No se recibió información del servidor.");
            finishUpdatingRepos(message: "Error: No se recibió información del servidor.", delay: 3.5)
            return
        }
        
        do {
            let feed = try JSONDecoder().decode(AltStoreFeed.self, from: data)
            let sourceName = feed.name ?? "Repositorio Nuevo"
            let newSource = AltStoreSource(name: sourceName, url: url, iconURL: feed.iconURL, isActive: true)
            log("✅ Decodificación exitosa: \(feed.apps.count) apps encontradas en '\(sourceName)'.")

            DispatchQueue.main.async {
                self.repoUpdateStatus = "Instalando Repo: \(sourceName)"
                if self.sources.contains(where: { $0.url == url }) {
                    self.log("⚠️ Error: Este repositorio ya existe.")
                    self.repoUpdateStatus = "La fuente ya existe"
                    self.showSourceExistsAlert = true
                    return
                }
                
                self.sources.append(newSource)
                self.log("✍️ Fuente '\(sourceName)' añadida a la lista.")
                
                let existingAppIDs = Set(self.apps.map { $0.bundleIdentifier })
                let newAppsToAdd = feed.apps.filter { !existingAppIDs.contains($0.bundleIdentifier) }
                
                if !newAppsToAdd.isEmpty {
                    self.apps.append(contentsOf: newAppsToAdd)
                    self.apps.sort { $0.name < $1.name }
                    self.log("📲 \(newAppsToAdd.count) nuevas apps añadidas a la tienda.")
                }
                
                let finalMessage = "Repositorio '\(sourceName)' añadido."
                self.log("🎉 \(finalMessage)"); self.finishUpdatingRepos(message: finalMessage)
            }
        } catch let decodingError as DecodingError {
            // Simplified error message for brevity
            let errorMessage = "Error de formato JSON: El archivo del repositorio está corrupto o no es válido."
            log("🛑 \(errorMessage) - \(decodingError.localizedDescription)")
            finishUpdatingRepos(message: errorMessage, delay: 5)
        } catch {
            let msg = "Ocurrió un error inesperado: \(error.localizedDescription)"
            log("🛑 \(msg)"); finishUpdatingRepos(message: msg, delay: 3.5)
        }
    }
    
    private func finishUpdatingRepos(message: String, delay: Double = 2.0) {
        DispatchQueue.main.async {
            self.repoUpdateStatus = message
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.isUpdatingRepos = false
                self.repoDownloadProgress = 0.0
            }
        }
    }
    
    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logMessage = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.activityLog.append(logMessage)
        }
    }
    
    // MARK: - Source Management
    func deleteSource(_ source: AltStoreSource) {
        recentlyDeletedSources = [source]
        sources.removeAll { $0.id == source.id }
        fetchApps()
        showUndoAlert = true
    }
    
    func undoDelete() {
        sources.append(contentsOf: recentlyDeletedSources)
        recentlyDeletedSources.removeAll()
        fetchApps()
    }
    
    // MARK: - URLSessionDownloadDelegate (Repo Downloads)
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard downloadTask.taskIdentifier == repoDownloadTaskIdentifier else { return }
        log("✅ Tarea \(downloadTask.taskIdentifier) finalizada.")
        guard let repoURL = self.repoDownloadURL, let data = try? Data(contentsOf: location) else {
            processDownloadedRepo(url: self.repoDownloadURL ?? "", data: nil, error: nil)
            return
        }
        processDownloadedRepo(url: repoURL, data: data, error: nil)
        repoDownloadTaskIdentifier = nil
        repoDownloadURL = nil
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error, task.taskIdentifier == repoDownloadTaskIdentifier else { return }
        log("‼️ Tarea \(task.taskIdentifier) completada con error: \(error.localizedDescription)")
        processDownloadedRepo(url: self.repoDownloadURL ?? "", data: nil, error: error)
        repoDownloadTaskIdentifier = nil
        repoDownloadURL = nil
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard downloadTask.taskIdentifier == repoDownloadTaskIdentifier, totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.repoDownloadProgress = progress }
    }
}