import SwiftUI
import Combine
import Components // Importamos el nuevo archivo de componentes

// MARK: - App Entry Point
@main
struct SwiftStoreApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
                .onShake {
                    NotificationCenter.default.post(name: .shakeToUndo, object: nil)
                }
        }
    }
}

// MARK: - Shake Detection Logic
extension Notification.Name {
    static let shakeToUndo = Notification.Name("shakeToUndo")
}

struct ShakeDetector: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeViewController { return ShakeViewController() }
    func updateUIViewController(_ uiViewController: ShakeViewController, context: Context) {}
}

class ShakeViewController: UIViewController {
    override func becomeFirstResponder() -> Bool { return true }
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .shakeToUndo, object: nil) }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.background(ShakeDetector())
            .onReceive(NotificationCenter.default.publisher(for: .shakeToUndo)) { _ in action() }
    }
    
    @ViewBuilder
    func hideListBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self.onAppear { UITableView.appearance().backgroundColor = .clear }
        }
    }
}

// MARK: - Models
struct AltStoreSource: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var iconURL: String?
    var isActive: Bool = true
}

struct AppVersion: Codable, Hashable {
    let version: String
    let date: String
    let downloadURL: String
    let size: Int64?
}

struct AltStoreApp: Identifiable, Codable, Hashable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let developerName: String
    let localizedDescription: String?
    let iconURL: String?
    let versions: [AppVersion]

    var version: String {
        return versions.first?.version ?? "N/A"
    }

    var downloadURL: String {
        return versions.first?.downloadURL ?? ""
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(bundleIdentifier) }
    static func ==(lhs: AltStoreApp, rhs: AltStoreApp) -> Bool { return lhs.bundleIdentifier == rhs.bundleIdentifier }
}

struct AltStoreFeed: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, iconURL, apps
    }
    let name: String?
    let iconURL: String?
    let apps: [AltStoreApp]

    // Decodificador personalizado para ignorar apps con formato incorrecto.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)

        var appsContainer = try container.nestedUnkeyedContainer(forKey: .apps)        
        var decodedApps: [AltStoreApp] = []

        while !appsContainer.isAtEnd {
            // Usamos un bloque do-catch para decodificar cada app individualmente.
            // Si una app falla, la saltamos en lugar de fallar toda la decodificación.
            do {
                let app = try appsContainer.decode(AltStoreApp.self)
                decodedApps.append(app)
            } catch {
                // Si una app no se puede decodificar, debemos avanzar el índice del
                // contenedor para evitar un bucle infinito. `superDecoder()` hace
                // exactamente eso: consume el siguiente elemento y lo devuelve como un
                // nuevo decodificador, que podemos ignorar de forma segura.
                _ = try? appsContainer.superDecoder()
            }
        }
        self.apps = decodedApps
    }
}

// MARK: - View Model & Download Manager
class AppViewModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var sources: [AltStoreSource] = [] { didSet { saveSources() } }
    @Published var apps: [AltStoreApp] = []
    
    // Configuraciones
    @AppStorage("asyncRepoSync") var asyncRepoSync: Bool = true
    @AppStorage("autoUpdateApps") var autoUpdateApps: Bool = false
    @AppStorage("wifiOnly") var wifiOnly: Bool = true
    @AppStorage("amoledPitchBlack") var amoledPitchBlack: Bool = true
    @AppStorage("downloadFolder") var downloadFolder: String = "Documentos"
    @AppStorage("enableAnimatedBackground") var enableAnimatedBackground: Bool = true
    @AppStorage("enableCreditsGlow") var enableCreditsGlow: Bool = false

    // Estado de interfaz
    @Published var searchText: String = ""
    @Published var downloadedFiles: [URL] = []
    @Published var downloadedApps: Set<String> = []
    
    // Estatus de Actualización de Fuentes
    @Published var isUpdatingRepos: Bool = false
    @Published var repoUpdateStatus: String = ""
    @Published var repoDownloadProgress: Double = 0.0
    @Published var activityLog: [String] = []
    
    // Cola de Descargas
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadQueue: [AltStoreApp] = []
    private var currentDownload: AltStoreApp?
    private var downloadSession: URLSession!
    private var repoDownloadSession: URLSession! // Sesión dedicada para añadir repositorios
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var taskAppMap: [Int: AltStoreApp] = [:]
    private var repoDownloadTaskIdentifier: Int?
    private var repoDownloadURL: String?
    
    // Variables de Undo
    @Published var recentlyDeletedSources: [AltStoreSource] = []
    @Published var showUndoAlert: Bool = false
    
    override init() {
        super.init()
        // Sesión para descargas de apps (IPA), con un timeout de conexión largo.
        let appConfig = URLSessionConfiguration.default
        appConfig.timeoutIntervalForRequest = 60.0
        self.downloadSession = URLSession(configuration: appConfig, delegate: self, delegateQueue: nil)
        
        // Sesión para añadir nuevos repositorios (JSON), con un timeout de recurso estricto.
        // Esto cancela la descarga completa si tarda más de 10 segundos.
        let repoConfig = URLSessionConfiguration.default
        repoConfig.timeoutIntervalForResource = 10.0 // Timeout de 10 segundos para toda la descarga.
        self.repoDownloadSession = URLSession(configuration: repoConfig, delegate: self, delegateQueue: nil)
        
        loadSources()
        checkDownloadedFiles()
        fetchApps()
        refreshFilesList()
    }
    
    // MARK: Persistencia
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
            sources = [AltStoreSource(name: "AltStore Official", url: "https://apps.altstore.io", iconURL: "https://altstore.io/altstore-icon.png", isActive: true)]
        }
    }
    
    // MARK: Funciones de Red (Con Estatus y Errores Detallados)
    func addSource(url: String) {
        guard let validURL = URL(string: url) else {
            // La validación de canOpenURL no es fiable para URLs de red.
            finishUpdatingRepos(message: "Error: La URL no parece ser válida.", delay: 3.5)
            return
        }
        
        DispatchQueue.main.async {
            self.activityLog.removeAll() // Limpiar el registro para la nueva operación.
            self.log("▶️ Iniciando adición de fuente: \(url)")
            self.isUpdatingRepos = true
            self.repoUpdateStatus = "Descargando JSON del nuevo repositorio..."
            self.repoDownloadProgress = 0.01 // Iniciar progreso visual para mostrar la barra.
        }
        
        log("⬇️ Creando tarea de descarga con timeout de recurso de 10s.")
        // Guardamos la URL para usarla en los métodos del delegado de URLSession.
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
        
        // Se crea una sesión específica para la sincronización con un timeout más corto.
        // Esto evita que una fuente lenta o que no responde bloquee la actualización completa.
        let syncConfig = URLSessionConfiguration.default
        syncConfig.timeoutIntervalForRequest = 30.0 // Timeout de 30 segundos.
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
                        // 1. Decodificar en el hilo de URLSession (background)
                        let feed = try JSONDecoder().decode(AltStoreFeed.self, from: data)
                        DispatchQueue.main.async {
                            let msg = "Procesando apps de: \(feed.name ?? source.name)"
                            self.repoUpdateStatus = msg; self.log("⚙️ \(msg)")
                        }
                        // 2. Procesar y acumular en un hilo dedicado para no bloquear la red ni la UI
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
        
        group.notify(queue: .main) {
            // 3. Una vez todas las fuentes han sido procesadas, actualiza la UI una sola vez.
            let uniqueApps = Array(Set(allNewApps))
            self.apps = uniqueApps.sorted { $0.name < $1.name }
            let msg = "Sincronización Completada"
            self.log("✅ \(msg): \(uniqueApps.count) apps únicas cargadas."); self.finishUpdatingRepos(message: msg)
        }
    }
    
    private func processDownloadedRepo(url: String, data: Data?, error: Error?) {
        if let error = error {
            let errorMessage: String
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    errorMessage = "Error: La solicitud tardó más de 10 segundos (timeout)."
                case .cannotFindHost:
                    errorMessage = "Error: No se pudo encontrar el host. Revisa la URL."
                default:
                    errorMessage = "Fallo de red: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Error inesperado: \(error.localizedDescription)"
            }
            log("🛑 \(errorMessage)")
            finishUpdatingRepos(message: errorMessage, delay: 3.5)
            return
        }
        
        guard let data = data else {
            log("🛑 Error: No se recibió información del servidor (data es nulo).")
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
                    let msg = "Error: Este repositorio ya existe."
                    self.log("⚠️ \(msg)"); self.finishUpdatingRepos(message: msg)
                    return
                }
                
                // LÓGICA MEJORADA: Añadir fuente y apps sin llamar a fetchApps()
                self.sources.append(newSource)
                self.log("✍️ Fuente '\(sourceName)' añadida a la lista.")
                
                let existingAppIDs = Set(self.apps.map { $0.bundleIdentifier })
                let newAppsToAdd = feed.apps.filter { !existingAppIDs.contains($0.bundleIdentifier) }
                
                if !newAppsToAdd.isEmpty {
                    self.apps.append(contentsOf: newAppsToAdd)
                    self.apps.sort { $0.name < $1.name } // Mantener orden
                    self.log("📲 \(newAppsToAdd.count) nuevas apps añadidas a la tienda.")
                }
                
                let finalMessage = "Repositorio '\(sourceName)' añadido."
                self.log("🎉 \(finalMessage)"); self.finishUpdatingRepos(message: finalMessage)
            }
        } catch let decodingError as DecodingError {
            var errorMessage = "Error de formato JSON: "
            switch decodingError {
            case .keyNotFound(let key, let context): errorMessage += "Falta la clave '\(key.stringValue)' en \(context.codingPath.map { $0.stringValue }.joined(separator: "."))."
            case .typeMismatch(_, let context): errorMessage += "Tipo de dato incorrecto en \(context.codingPath.map { $0.stringValue }.joined(separator: "."))."
            case .valueNotFound(_, let context): errorMessage += "Valor nulo inesperado en \(context.codingPath.map { $0.stringValue }.joined(separator: "."))."
            case .dataCorrupted(let context): errorMessage += "El JSON está corrupto. \(context.debugDescription)"
            @unknown default: errorMessage += "Error desconocido al procesar el JSON."
            }
            log("🛑 \(errorMessage)")
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
                self.repoDownloadProgress = 0.0 // Limpiar la barra de progreso
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
    
    // MARK: Gestión de Deshacer
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
    
    // MARK: Gestor de Archivos
    var downloadsDirectory: URL {
        let directory: FileManager.SearchPathDirectory = downloadFolder == "Documentos" ? .documentDirectory : .cachesDirectory
        return FileManager.default.urls(for: directory, in: .userDomainMask).first!
    }
    
    func refreshFilesList() {
        if let files = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            DispatchQueue.main.async { self.downloadedFiles = files.filter { $0.pathExtension == "ipa" } }
        }
    }
    
    func checkDownloadedFiles() {
        var existing: Set<String> = []
        if let files = try? FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path) {
            for file in files where file.hasSuffix(".ipa") { existing.insert(file.replacingOccurrences(of: ".ipa", with: "")) }
        }
        DispatchQueue.main.async { self.downloadedApps = existing }
    }
    
    func deleteAppFile(app: AltStoreApp) {
        let fileURL = downloadsDirectory.appendingPathComponent("\(app.bundleIdentifier).ipa")
        try? FileManager.default.removeItem(at: fileURL)
        checkDownloadedFiles()
        refreshFilesList()
    }
    
    // MARK: Sistema de Cola de Descargas
    func startDownload(app: AltStoreApp) {
        if downloadedApps.contains(app.bundleIdentifier) || downloadQueue.contains(app) || currentDownload == app { return }
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
            finishDownloadProcessing(for: app.bundleIdentifier)
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
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Comprobar si es la descarga de un nuevo repositorio.
        if downloadTask.taskIdentifier == repoDownloadTaskIdentifier {
            log("✅ Tarea \(downloadTask.taskIdentifier) finalizada. Archivo temporal en: \(location.path)")
            guard let repoURL = self.repoDownloadURL, let data = try? Data(contentsOf: location) else {
                processDownloadedRepo(url: self.repoDownloadURL ?? "", data: nil, error: nil)
                return
            }
            processDownloadedRepo(url: repoURL, data: data, error: nil)
            
            // Limpieza
            self.repoDownloadTaskIdentifier = nil
            self.repoDownloadURL = nil
        }
        // O si es la descarga de una app.
        else if let app = taskAppMap[downloadTask.taskIdentifier] {
            let dest = downloadsDirectory.appendingPathComponent("\(app.bundleIdentifier).ipa")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: location, to: dest)
            
            DispatchQueue.main.async {
                self.downloadedApps.insert(app.bundleIdentifier)
                self.refreshFilesList()
            }
            finishDownloadProcessing(for: app.bundleIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Comprobar si es un error en la descarga de un nuevo repositorio.
        if let error = error, task.taskIdentifier == repoDownloadTaskIdentifier {
            log("‼️ Tarea \(task.taskIdentifier) completada con error: \(error.localizedDescription)")
            processDownloadedRepo(url: self.repoDownloadURL ?? "", data: nil, error: error)
            
            // Limpieza
            self.repoDownloadTaskIdentifier = nil
            self.repoDownloadURL = nil
            return
        }
        
        // O si es un error en la descarga de una app.
        if let _ = error, let app = taskAppMap[task.taskIdentifier] {
            finishDownloadProcessing(for: app.bundleIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Comprobar si es el progreso de la descarga de un nuevo repositorio.
        if downloadTask.taskIdentifier == repoDownloadTaskIdentifier, totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async { self.repoDownloadProgress = progress }
        }
        // O si es el progreso de la descarga de una app.
        else if let app = taskAppMap[downloadTask.taskIdentifier], totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async { self.downloadProgress[app.bundleIdentifier] = progress }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var scrollObserver = ScrollObserver()
    @State private var selectedTab: Int = 0 // Controla la pestaña seleccionada
    @State private var lastStoreTabTapTime: Date? // Para detectar doble toque en la pestaña de la tienda
    @State private var showingLogView = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) { // Usamos la selección controlada
                NavigationView { StoreView() }
                    .navigationViewStyle(.stack)
                    .environmentObject(viewModel)
                    .tabItem { Label("Tienda", systemImage: "square.stack.3d.down.right.fill") }
                
                NavigationView { SourcesView() }
                    .navigationViewStyle(.stack)
                    .environmentObject(viewModel)
                    .tabItem { Label("Fuentes", systemImage: "link") }
                
                NavigationView { FilesView() }
                    .navigationViewStyle(.stack)
                    .environmentObject(viewModel)
                    .tabItem { Label("Archivos", systemImage: "folder.fill") }
                
                NavigationView { SettingsView() }
                    .navigationViewStyle(.stack)
                    .environmentObject(viewModel)
                    .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
            }
            .onChange(of: selectedTab) { newTab in
                if newTab == 0 { // Si la pestaña de la tienda (índice 0) es seleccionada
                    if let lastTapTime = lastStoreTabTapTime, Date().timeIntervalSince(lastTapTime) < 0.3 {
                        // Doble toque detectado en la pestaña de la tienda
                        NotificationCenter.default.post(name: .doubleTapStoreTab, object: nil)
                        lastStoreTabTapTime = nil // Reiniciar para evitar triple toques
                    } else {
                        lastStoreTabTapTime = Date()
                    }
                } else {
                    lastStoreTabTapTime = nil // Reiniciar si se selecciona otra pestaña
                }
            }
            .accentColor(.cyan)
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 15.0, *) { UITabBar.appearance().scrollEdgeAppearance = appearance }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shakeToUndo)) { _ in
                if !viewModel.recentlyDeletedSources.isEmpty { viewModel.showUndoAlert = true }
            }
            .alert(isPresented: $viewModel.showUndoAlert) {
                Alert(
                    title: Text("Deshacer acción"),
                    message: Text("¿Deseas restaurar las fuentes eliminadas recientemente?"),
                    primaryButton: .default(Text("Deshacer")) { viewModel.undoDelete() },
                    secondaryButton: .cancel()
                )
            }
            
            if viewModel.isUpdatingRepos {
                Button(action: { showingLogView = true }) {
                    LiveStatusOverlay(status: viewModel.repoUpdateStatus, progress: viewModel.repoDownloadProgress)
                }
                .buttonStyle(PlainButtonStyle()) // Evita que el botón altere el estilo del overlay.
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
                .padding(.bottom, 60)
            }
        }
        .sheet(isPresented: $showingLogView) {
            ActivityLogView()
                .environmentObject(viewModel)
        }
        .environmentObject(scrollObserver) // Inyectamos el observador en el entorno
    }
}

// Menú Flotante Visual (Live Status)
struct LiveStatusOverlay: View {
    var status: String
    var progress: Double
    var body: some View {
        HStack(spacing: 15) {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .cyan))
            VStack(alignment: .leading, spacing: 2) {
                Text("Estatus de la Actualización")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(status)
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                if progress > 0 && progress < 1 {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                        .animation(.easeInOut, value: progress)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "1C1C1E").opacity(0.95))
                .shadow(color: .cyan.opacity(0.2), radius: 15, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}
