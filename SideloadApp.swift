import SwiftUI
import Combine

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
    // Ignorar el campo 'identifier' del JSON para evitar errores de decodificación.
    private enum CodingKeys: String, CodingKey {
        case name, iconURL, apps
    }
    let name: String?
    let iconURL: String?
    let apps: [AltStoreApp]
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

    // Estado de interfaz
    @Published var searchText: String = ""
    @Published var downloadedFiles: [URL] = []
    @Published var downloadedApps: Set<String> = []
    
    // Estatus de Actualización de Fuentes
    @Published var isUpdatingRepos: Bool = false
    @Published var repoUpdateStatus: String = ""
    
    // Cola de Descargas
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadQueue: [AltStoreApp] = []
    private var currentDownload: AltStoreApp?
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var taskAppMap: [Int: AltStoreApp] = [:]
    
    // Variables de Undo
    @Published var recentlyDeletedSources: [AltStoreSource] = []
    @Published var showUndoAlert: Bool = false
    
    override init() {
        super.init()
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
        guard let validURL = URL(string: url), UIApplication.shared.canOpenURL(validURL) else {
            finishUpdatingRepos(message: "Error: La URL ingresada no es válida.", delay: 3.5)
            return
        }
        DispatchQueue.main.async {
            self.isUpdatingRepos = true
            self.repoUpdateStatus = "Descargando JSON del nuevo repositorio..."
        }
        
        URLSession.shared.dataTask(with: validURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                let errorMessage: String
                if let urlError = error as? URLError, urlError.code == .cannotFindHost {
                    errorMessage = "Error: No se pudo encontrar el host. Revisa la URL."
                } else {
                    errorMessage = "Fallo de red: \(error.localizedDescription)"
                }
                DispatchQueue.main.async { self.finishUpdatingRepos(message: errorMessage, delay: 3.5) }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async { self.finishUpdatingRepos(message: "Error: No se recibió información del servidor.", delay: 3.5) }
                return
            }
            
            do {
                let feed = try JSONDecoder().decode(AltStoreFeed.self, from: data)
                DispatchQueue.main.async {
                    let sourceName = feed.name ?? "Repositorio Nuevo"
                    self.repoUpdateStatus = "Instalando Repo: \(sourceName)"
                    let newSource = AltStoreSource(name: sourceName, url: url, iconURL: feed.iconURL, isActive: true)
                    
                    if !self.sources.contains(where: { $0.url == url }) {
                        self.sources.append(newSource)
                        self.fetchApps()
                    } else {
                        self.finishUpdatingRepos(message: "Error: Este repositorio ya existe.")
                    }
                }
            } catch let decodingError as DecodingError {
                var errorMessage = "Error de formato JSON: "
                switch decodingError {
                case .keyNotFound(let key, let context):
                    errorMessage += "Falta la clave '\(key.stringValue)' en \(context.codingPath.map { $0.stringValue }.joined(separator: "."))."
                case .typeMismatch(_, let context):
                    errorMessage += "Tipo de dato incorrecto en \(context.codingPath.map { $0.stringValue }.joined(separator: "."))."
                case .valueNotFound(_, let context):
                    errorMessage += "Valor nulo inesperado en \(context.codingPath.map { $0.stringValue }.joined(separator: "."))."
                case .dataCorrupted(let context):
                    errorMessage += "El JSON está corrupto. \(context.debugDescription)"
                @unknown default:
                    errorMessage += "Error desconocido al procesar el JSON."
                }
                DispatchQueue.main.async { self.finishUpdatingRepos(message: errorMessage, delay: 5) }
            }
        }.resume()
    }
    
    func fetchApps() {
        let activeSources = sources.filter { $0.isActive }
        if activeSources.isEmpty {
            apps.removeAll()
            return
        }
        
        DispatchQueue.main.async {
            self.isUpdatingRepos = true
            self.repoUpdateStatus = "Sincronizando \(activeSources.count) fuentes..."
            self.apps.removeAll()
        }
        
        let group = DispatchGroup()
        
        for source in activeSources {
            guard let url = URL(string: source.url) else { continue }
            group.enter()
            
            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                defer { group.leave() }
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async { self.repoUpdateStatus = "Error en \(source.name): \(error.localizedDescription)" }
                    return
                }
                
                if let data = data {
                    do {
                        let feed = try JSONDecoder().decode(AltStoreFeed.self, from: data)
                        DispatchQueue.main.async {
                            self.repoUpdateStatus = "Procesando apps de: \(feed.name ?? source.name)"
                            for newApp in feed.apps {
                                if !self.apps.contains(where: { $0.bundleIdentifier == newApp.bundleIdentifier }) {
                                    self.apps.append(newApp)
                                }
                            }
                        }
                    } catch {
                        DispatchQueue.main.async { self.repoUpdateStatus = "JSON corrupto en: \(source.name)" }
                    }
                }
            }.resume()
        }
        
        group.notify(queue: .main) {
            self.finishUpdatingRepos(message: "Sincronización Completada")
        }
    }
    
    private func finishUpdatingRepos(message: String, delay: Double = 2.0) {
        self.repoUpdateStatus = message
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.isUpdatingRepos = false
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
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        let task = session.downloadTask(with: url)
        downloadTasks[nextApp.bundleIdentifier] = task
        taskAppMap[task.taskIdentifier] = nextApp
        isDownloading[nextApp.bundleIdentifier] = true
        downloadProgress[nextApp.bundleIdentifier] = 0.01
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
        isDownloading[identifier] = false
        downloadProgress[identifier] = 0.0
        downloadTasks[identifier] = nil
        if currentDownload?.bundleIdentifier == identifier {
            currentDownload = nil
            processDownloadQueue()
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let app = taskAppMap[downloadTask.taskIdentifier] else { return }
        let dest = downloadsDirectory.appendingPathComponent("\(app.bundleIdentifier).ipa")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
        
        DispatchQueue.main.async {
            self.downloadedApps.insert(app.bundleIdentifier)
            self.refreshFilesList()
            self.finishDownloadProcessing(for: app.bundleIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let app = taskAppMap[downloadTask.taskIdentifier], totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.downloadProgress[app.bundleIdentifier] = progress }
    }
}

// MARK: - Animated Blob Background
struct BlobBackgroundView: View {
    @AppStorage("enableAnimatedBackground") var enableAnimatedBackground: Bool = true
    @State private var phase: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if enableAnimatedBackground {
                RoundedRectangle(cornerRadius: 150, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "5E35B1"), Color(hex: "283593")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 320, height: 350)
                    .rotationEffect(.degrees(phase * 40))
                    .scaleEffect(1 + CGFloat(sin(phase)) * 0.1)
                    .blur(radius: 60)
                    .offset(x: sin(phase * 1.5) * 80, y: cos(phase * 1.2) * 80)
                
                RoundedRectangle(cornerRadius: 120, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "0288D1"), .clear], startPoint: .bottom, endPoint: .top))
                    .frame(width: 380, height: 300)
                    .rotationEffect(.degrees(-phase * 30))
                    .blur(radius: 80)
                    .offset(x: cos(phase * 0.8) * -60, y: sin(phase * 1.1) * 100)
            }
        }
        .onAppear {
            if enableAnimatedBackground {
                withAnimation(.linear(duration: 15).repeatForever(autoreverses: true)) { phase = .pi * 2 }
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var showingShakeUndo = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
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
            .accentColor(.cyan)
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 15.0, *) { UITabBar.appearance().scrollEdgeAppearance = appearance }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shakeToUndo)) { _ in
                if !viewModel.recentlyDeletedSources.isEmpty { showingShakeUndo = true }
            }
            .alert(isPresented: $showingShakeUndo) {
                Alert(
                    title: Text("Deshacer acción"),
                    message: Text("¿Deseas restaurar las fuentes eliminadas recientemente?"),
                    primaryButton: .default(Text("Deshacer")) { viewModel.undoDelete() },
                    secondaryButton: .cancel()
                )
            }
            
            if viewModel.isUpdatingRepos {
                LiveStatusOverlay(status: viewModel.repoUpdateStatus)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                    .padding(.bottom, 60)
            }
        }
    }
}

// Menú Flotante Visual (Live Status)
struct LiveStatusOverlay: View {
    var status: String
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

// MARK: - Store View
struct StoreView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    var filteredApps: [AltStoreApp] {
        viewModel.searchText.isEmpty ? viewModel.apps : viewModel.apps.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
    }
    
    var body: some View {
        ZStack {
            BlobBackgroundView()
            
            ScrollView {
                VStack(spacing: 15) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Buscar aplicaciones...", text: $viewModel.searchText)
                            .foregroundColor(.white)
                    }
                    .padding(12).background(Color.white.opacity(0.08)).cornerRadius(12).padding(.horizontal)
                    
                    if filteredApps.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.grid.2x2").font(.system(size: 50)).foregroundColor(.gray)
                            Text("No hay apps disponibles.").foregroundColor(.gray)
                        }.padding(.top, 50)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredApps) { app in
                                NavigationLink(destination: AppDetailView(app: app)) { AppCardView(app: app) }.buttonStyle(PlainButtonStyle())
                            }
                        }.padding(.bottom, 20)
                    }
                }
            }
        }.navigationTitle("SwiftStore")
    }
}

// MARK: - Components (Card & Detail)
struct AppCardView: View {
    let app: AltStoreApp
    var body: some View {
        LiquidGlassCard {
            HStack(spacing: 15) {
                AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                    if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                    else if phase.error != nil { Color.black.opacity(0.8) } // Color Oscuro estilo Google
                    else { ProgressView() }
                }.frame(width: 55, height: 55).cornerRadius(14)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                    Text(app.developerName).font(.system(size: 13, weight: .regular)).foregroundColor(.gray)
                }
                Spacer()
                DownloadIndicator(app: app)
            }
        }.padding(.horizontal)
    }
}

struct AppDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let app: AltStoreApp
    var body: some View {
        ZStack {
            BlobBackgroundView()
            ScrollView {
                VStack(spacing: 20) {
                    AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fit) }
                        else { RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.8)) } // Color Oscuro estilo Google
                    }.frame(width: 120, height: 120).cornerRadius(24).shadow(radius: 10)
                    
                    Text(app.name).font(.largeTitle).bold().foregroundColor(.white)
                    Text(app.version).font(.subheadline).foregroundColor(.cyan)
                    DownloadIndicator(app: app, isLarge: true)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Descripción").font(.headline).foregroundColor(.white)
                        Text(app.localizedDescription ?? "No hay descripción disponible.").foregroundColor(.gray).font(.body)
                    }.padding().background(Color.white.opacity(0.05)).cornerRadius(16).padding(.horizontal)
                }.padding(.vertical)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { viewModel.deleteAppFile(app: app); viewModel.startDownload(app: app) }) { Label("Volver a descargar", systemImage: "arrow.clockwise.icloud") }
                    Button(action: { viewModel.deleteAppFile(app: app) }) { Label("Eliminar", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").foregroundColor(.white).font(.headline) } // Icono nativo de 3 puntos
            }
        }
    }
}

// MARK: - Download Indicator
struct DownloadIndicator: View {
    @EnvironmentObject var viewModel: AppViewModel
    let app: AltStoreApp
    var isLarge: Bool = false
    
    var body: some View {
        let isDownloading = viewModel.isDownloading[app.bundleIdentifier] ?? false
        let isQueued = viewModel.downloadQueue.contains(app)
        let progress = viewModel.downloadProgress[app.bundleIdentifier] ?? 0.0
        let isDownloaded = viewModel.downloadedApps.contains(app.bundleIdentifier)
        
        let size: CGFloat = isLarge ? 50 : 32
        let fontSize: CGFloat = isLarge ? 30 : 28
        
        ZStack {
            if isDownloading {
                Button(action: { viewModel.cancelDownload(app: app) }) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 3).frame(width: size, height: size)
                        Circle().trim(from: 0.0, to: CGFloat(progress)).stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: size, height: size)
                        Rectangle().fill(Color.cyan).frame(width: size/3.5, height: size/3.5).cornerRadius(2)
                    }
                }
            } else if isQueued {
                Button(action: { viewModel.cancelDownload(app: app) }) {
                    Image(systemName: "clock.fill").font(.system(size: fontSize)).foregroundColor(.orange)
                }
            } else if isDownloaded {
                Image(systemName: "checkmark.circle.fill").font(.system(size: fontSize)).foregroundColor(.green)
            } else {
                Button(action: { viewModel.startDownload(app: app) }) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: fontSize)).foregroundColor(.cyan)
                }
            }
        }.frame(width: isLarge ? 60 : 40, height: isLarge ? 60 : 40)
    }
}

// MARK: - Sources View
struct SourcesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var newRepoURL: String = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    
    var body: some View {
        ZStack {
            BlobBackgroundView()
            
            VStack(spacing: 20) {
                if editMode == .inactive {
                    LiquidGlassCard {
                        VStack(spacing: 10) {
                            TextField("URL (http://... o https://...)", text: $newRepoURL)
                                .padding(12).background(Color.white.opacity(0.08)).cornerRadius(8).foregroundColor(.white).keyboardType(.URL).autocapitalization(.none)
                            
                            Button(action: { viewModel.addSource(url: newRepoURL); newRepoURL = "" }) {
                                Text("Añadir Repositorio").fontWeight(.bold).foregroundColor(.black).frame(maxWidth: .infinity).padding(12).background(Color.cyan).cornerRadius(10)
                            }
                        }
                    }.padding(.horizontal).padding(.top)
                }
                
                List(selection: $selection) {
                    ForEach($viewModel.sources) { $source in
                        HStack(spacing: 15) {
                            AsyncImage(url: URL(string: source.iconURL ?? "")) { phase in
                                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                                else { Image(systemName: "server.rack").foregroundColor(.gray) }
                            }.frame(width: 40, height: 40).cornerRadius(8)
                            
                            VStack(alignment: .leading) {
                                Text(source.name).foregroundColor(.white).fontWeight(.bold)
                                Text(source.url).font(.caption).foregroundColor(.gray).lineLimit(1)
                            }
                            Spacer()
                            
                            if editMode == .inactive {
                                Toggle("", isOn: $source.isActive)
                                    .labelsHidden()
                                    .onChange(of: source.isActive) { _ in viewModel.fetchApps() }
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                        .onLongPressGesture { if viewModel.sources.count >= 2 { withAnimation { editMode = .active } } }
                    }
                    .onDelete { indexSet in
                        if let index = indexSet.first { viewModel.deleteSource(viewModel.sources[index]) }
                    }
                }
                .environment(\.editMode, $editMode)
                .hideListBackground()
            }
            
            if editMode == .active {
                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        Button(role: .destructive, action: {
                            let sourcesToDelete = viewModel.sources.filter { selection.contains($0.id) }
                            viewModel.recentlyDeletedSources = sourcesToDelete
                            viewModel.sources.removeAll { selection.contains($0.id) }
                            viewModel.fetchApps()
                            viewModel.showUndoAlert = true
                            selection.removeAll()
                            editMode = .inactive
                        }) {
                            VStack { Image(systemName: "trash"); Text("Eliminar") }
                        }.disabled(selection.isEmpty)
                        
                        Button(action: {
                            for i in viewModel.sources.indices { if selection.contains(viewModel.sources[i].id) { viewModel.sources[i].isActive.toggle() } }
                            viewModel.fetchApps()
                            selection.removeAll()
                            editMode = .inactive
                        }) {
                            VStack { Image(systemName: "switch.2"); Text("Alternar") }
                        }.disabled(selection.isEmpty)
                        
                        Button(action: { selection.removeAll(); editMode = .inactive }) {
                            VStack { Image(systemName: "xmark.circle"); Text("Cancelar") }
                        }
                    }
                    .padding().background(.ultraThinMaterial).cornerRadius(20).padding()
                }
            }
        }
        .navigationTitle("Fuentes")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { viewModel.fetchApps() }) { Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.cyan) }
            }
        }
    }
}

// MARK: - Files Manager View
struct FilesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    var body: some View {
        ZStack {
            BlobBackgroundView()
            if viewModel.downloadedFiles.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 60)).foregroundColor(.gray)
                    Text("No hay archivos descargados").foregroundColor(.gray)
                }
            } else {
                List {
                    ForEach(viewModel.downloadedFiles, id: \.self) { fileURL in
                        HStack {
                            Image(systemName: "doc.zipper").font(.system(size: 30)).foregroundColor(.cyan).padding(.trailing, 8)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fileURL.lastPathComponent).foregroundColor(.white).font(.headline).lineLimit(1)
                                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                                   let fileSize = attributes[.size] as? Int64 {
                                    Text(formatBytes(fileSize)).font(.caption).foregroundColor(.gray)
                                }
                            }
                        }.padding(.vertical, 4).listRowBackground(Color.white.opacity(0.05))
                    }.onDelete { indexSet in
                        indexSet.forEach { index in try? FileManager.default.removeItem(at: viewModel.downloadedFiles[index]) }
                        viewModel.refreshFilesList()
                        viewModel.checkDownloadedFiles()
                    }
                }.hideListBackground()
            }
        }
        .navigationTitle("Archivos")
        .onAppear { viewModel.refreshFilesList() }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var randomImageName: String = ""
    
    let renders = ["3D_Render_1", "3D_Render_2", "3D_Render_3"]
    let folders = ["Documentos", "Caché"]
    
    var body: some View {
        ZStack {
            BlobBackgroundView()
            
            Form {
                Section(header: Text("Sincronización").foregroundColor(.cyan)) {
                    Toggle("Async Repo Sync", isOn: $viewModel.asyncRepoSync)
                    Toggle("Actualizar apps automáticamente", isOn: $viewModel.autoUpdateApps)
                }.listRowBackground(Color.white.opacity(0.08))
                
                Section(header: Text("Archivos").foregroundColor(.cyan)) {
                    Picker("Carpeta de Descargas", selection: $viewModel.downloadFolder) {
                        ForEach(folders, id: \.self) { folder in Text(folder).tag(folder) }
                    }.pickerStyle(SegmentedPickerStyle()).padding(.vertical, 5)
                }.listRowBackground(Color.white.opacity(0.08))
                
                Section(header: Text("Apariencia").foregroundColor(.cyan)) {
                    Toggle("Modo AMOLED (Pitch Black)", isOn: $viewModel.amoledPitchBlack)
                    Toggle("Fondo Animado (Burbujas)", isOn: $viewModel.enableAnimatedBackground)
                }.listRowBackground(Color.white.opacity(0.08))
                
                Section(header: Text("Acerca de").foregroundColor(.cyan)) {
                    VStack(alignment: .center, spacing: 10) {
                        Image(randomImageName.isEmpty ? "default_render" : randomImageName)
                            .resizable().aspectRatio(contentMode: .fit).frame(height: 120).cornerRadius(15)
                            .onAppear { randomImageName = renders.randomElement() ?? "" }
                        Text("SwiftStore v3.1.2").font(.headline).foregroundColor(.white)
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    
                    NavigationLink(destination: CreditsView()) {
                        HStack {
                            Text("Desarrollador").foregroundColor(.primary)
                            Spacer()
                            Text("elmendezz").font(.system(.body, design: .monospaced)).foregroundColor(.cyan)
                        }
                    }
                }.listRowBackground(Color.white.opacity(0.08))
            }.hideListBackground()
        }
        .navigationTitle("Configuración")
    }
}

// MARK: - Liquid Glass Component & Colors
struct LiquidGlassCard<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding()
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)).background(.ultraThinMaterial.opacity(0.3)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)))
            .shadow(color: Color.black.opacity(0.6), radius: 10, x: 0, y: 5)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
}
