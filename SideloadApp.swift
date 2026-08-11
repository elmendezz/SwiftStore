//
//  SideloadApp.swift
//  SwiftStore
//
//  CHANGELOG:
//  - Version 2.1.0: Compatibilidad con iOS 15 (NavigationView y backgrounds),
//    Gestor de Archivos `.ipa` integrado, selector de carpeta de descargas,
//    y un Easter Egg escondido en el código.
//

import SwiftUI
import Combine

// ==========================================
// 🥚 EASTER EGG:
// ¡Hola! Fui asistido por Gemini 🤖✨ en la
// creación de esta increíble tienda.
// ==========================================

// MARK: - App Entry Point
@main
struct SwiftStoreApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - View Extensions for iOS 15 Compatibility
extension View {
    @ViewBuilder
    func hideListBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self.onAppear {
                UITableView.appearance().backgroundColor = .clear
            }
        }
    }
}

// MARK: - Models
struct AltStoreSource: Identifiable, Codable {
    var id = UUID()
    var name: String
    var url: String
    var iconURL: String?
}

struct AltStoreApp: Identifiable, Codable, Hashable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let developerName: String
    let version: String
    let downloadURL: String
    let localizedDescription: String?
    let iconURL: String?
    let size: Int64? // Tamaño en bytes si está disponible
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
    static func ==(lhs: AltStoreApp, rhs: AltStoreApp) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

struct AltStoreFeed: Codable {
    let name: String
    let iconURL: String?
    let apps: [AltStoreApp]
}

// MARK: - View Model & Download Manager
class AppViewModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var sources: [AltStoreSource] = []
    @Published var apps: [AltStoreApp] = []
    
    // Settings
    @AppStorage("asyncRepoSync") var asyncRepoSync: Bool = true
    @AppStorage("autoUpdateApps") var autoUpdateApps: Bool = false
    @AppStorage("wifiOnly") var wifiOnly: Bool = true
    @AppStorage("amoledPitchBlack") var amoledPitchBlack: Bool = true
    @AppStorage("downloadFolder") var downloadFolder: String = "Documentos" // Nueva configuración

    @Published var searchText: String = ""
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadedApps: Set<String> = []
    
    // File Manager State
    @Published var downloadedFiles: [URL] = []
    
    // Scroll Velocity State for Background
    @Published var scrollVelocity: Double = 1.0
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var taskAppMap: [Int: AltStoreApp] = [:]
    
    override init() {
        super.init()
        loadDefaultSources()
        checkDownloadedFiles()
        fetchApps()
        refreshFilesList()
    }
    
    func loadDefaultSources() {
        if sources.isEmpty {
            sources = [
                AltStoreSource(name: "AltStore Official", url: "https://apps.altstore.io", iconURL: "https://altstore.io/altstore-icon.png")
            ]
        }
    }
    
    func addSource(url: String) {
        guard let validURL = URL(string: url), validURL.scheme != nil else { return }
        URLSession.shared.dataTask(with: validURL) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            if let feed = try? JSONDecoder().decode(AltStoreFeed.self, from: data) {
                DispatchQueue.main.async {
                    let newSource = AltStoreSource(name: feed.name, url: url, iconURL: feed.iconURL)
                    if !self.sources.contains(where: { $0.url == url }) {
                        self.sources.append(newSource)
                        self.apps.append(contentsOf: feed.apps)
                    }
                }
            }
        }.resume()
    }
    
    func fetchApps() {
        apps.removeAll()
        for source in sources {
            guard let url = URL(string: source.url) else { continue }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard let self = self, let data = data, error == nil else { return }
                if let feed = try? JSONDecoder().decode(AltStoreFeed.self, from: data) {
                    DispatchQueue.main.async {
                        for newApp in feed.apps {
                            if !self.apps.contains(where: { $0.bundleIdentifier == newApp.bundleIdentifier }) {
                                self.apps.append(newApp)
                            }
                        }
                    }
                }
            }.resume()
        }
    }
    
    // MARK: File Management
    var downloadsDirectory: URL {
        let directory: FileManager.SearchPathDirectory = downloadFolder == "Documentos" ? .documentDirectory : .cachesDirectory
        return FileManager.default.urls(for: directory, in: .userDomainMask).first!
    }
    
    func refreshFilesList() {
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            DispatchQueue.main.async {
                self.downloadedFiles = files.filter { $0.pathExtension == "ipa" }
            }
        }
    }
    
    func checkDownloadedFiles() {
        var existing: Set<String> = []
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(atPath: downloadsDirectory.path) {
            for file in files where file.hasSuffix(".ipa") {
                let id = file.replacingOccurrences(of: ".ipa", with: "")
                existing.insert(id)
            }
        }
        DispatchQueue.main.async { self.downloadedApps = existing }
    }
    
    func deleteAppFile(app: AltStoreApp) {
        let fileURL = downloadsDirectory.appendingPathComponent("\(app.bundleIdentifier).ipa")
        try? FileManager.default.removeItem(at: fileURL)
        checkDownloadedFiles()
        refreshFilesList()
    }
    
    // MARK: Download Logic
    func startDownload(app: AltStoreApp) {
        if downloadedApps.contains(app.bundleIdentifier) { return }
        
        guard let url = URL(string: app.downloadURL) else { return }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        let task = session.downloadTask(with: url)
        
        downloadTasks[app.bundleIdentifier] = task
        taskAppMap[task.taskIdentifier] = app
        
        isDownloading[app.bundleIdentifier] = true
        downloadProgress[app.bundleIdentifier] = 0.01
        task.resume()
    }
    
    func cancelDownload(app: AltStoreApp) {
        downloadTasks[app.bundleIdentifier]?.cancel()
        downloadTasks[app.bundleIdentifier] = nil
        isDownloading[app.bundleIdentifier] = false
        downloadProgress[app.bundleIdentifier] = 0.0
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let app = taskAppMap[downloadTask.taskIdentifier] else { return }
        let destinationURL = downloadsDirectory.appendingPathComponent("\(app.bundleIdentifier).ipa")
        
        try? FileManager.default.removeItem(at: destinationURL)
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
        } catch {
            print("Error al guardar: \(error)")
        }
        
        DispatchQueue.main.async {
            self.isDownloading[app.bundleIdentifier] = false
            self.downloadProgress[app.bundleIdentifier] = 1.0
            self.downloadedApps.insert(app.bundleIdentifier)
            self.refreshFilesList()
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let app = taskAppMap[downloadTask.taskIdentifier], totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.downloadProgress[app.bundleIdentifier] = progress
        }
    }
}

// MARK: - Animated Blob Background
struct BlobBackgroundView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var phase: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "4A148C"), Color(hex: "311B92")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: sin(phase) * 100, y: cos(phase) * 100)
            
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "1A237E"), .clear], startPoint: .bottom, endPoint: .top))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(x: cos(phase * 0.7) * -80, y: sin(phase * 0.5) * 120)
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .onChange(of: viewModel.scrollVelocity) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                // Background velocity modifier stub
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @StateObject private var viewModel = AppViewModel()
    
    var body: some View {
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
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
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
                GeometryReader { geo -> Color in
                    let velocity = abs(geo.frame(in: .global).minY)
                    DispatchQueue.main.async { viewModel.scrollVelocity = velocity }
                    return Color.clear
                }.frame(height: 0)
                
                VStack(spacing: 15) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Buscar aplicaciones...", text: $viewModel.searchText)
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    LazyVStack(spacing: 12) {
                        ForEach(filteredApps) { app in
                            NavigationLink(destination: AppDetailView(app: app)) {
                                AppCardView(app: app)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("SwiftStore")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { viewModel.fetchApps() }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.cyan)
                }
            }
        }
    }
}

// MARK: - App Card Component
struct AppCardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let app: AltStoreApp
    
    var body: some View {
        LiquidGlassCard {
            HStack(spacing: 15) {
                AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        Color.gray
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 55, height: 55)
                .cornerRadius(14)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text(app.developerName)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                DownloadIndicator(app: app)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - App Detail View
struct AppDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let app: AltStoreApp
    
    var body: some View {
        ZStack {
            BlobBackgroundView()
            
            ScrollView {
                VStack(spacing: 20) {
                    AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            RoundedRectangle(cornerRadius: 24).fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(width: 120, height: 120)
                    .cornerRadius(24)
                    .shadow(radius: 10)
                    
                    Text(app.name)
                        .font(.largeTitle).bold()
                        .foregroundColor(.white)
                    
                    Text(app.version)
                        .font(.subheadline)
                        .foregroundColor(.cyan)
                    
                    HStack(spacing: 20) {
                        DownloadIndicator(app: app, isLarge: true)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Descripción")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(app.localizedDescription ?? "No hay descripción disponible.")
                            .foregroundColor(.gray)
                            .font(.body)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        viewModel.deleteAppFile(app: app)
                        viewModel.startDownload(app: app)
                    }) {
                        Label("Volver a descargar", systemImage: "arrow.clockwise.icloud")
                    }
                    
                    Button(action: {
                        viewModel.deleteAppFile(app: app)
                    }) {
                        Label("Eliminar", systemImage: "trash")
                    }
                    
                    Button(action: {
                        viewModel.fetchApps()
                    }) {
                        Label("Recargar información", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.cyan)
                }
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
        let progress = viewModel.downloadProgress[app.bundleIdentifier] ?? 0.0
        let isDownloaded = viewModel.downloadedApps.contains(app.bundleIdentifier)
        
        let size: CGFloat = isLarge ? 50 : 32
        let fontSize: CGFloat = isLarge ? 30 : 28
        
        ZStack {
            if isDownloading {
                Button(action: { viewModel.cancelDownload(app: app) }) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 3).frame(width: size, height: size)
                        Circle()
                            .trim(from: 0.0, to: CGFloat(progress))
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: size, height: size)
                            .animation(.linear(duration: 0.2), value: progress)
                        Rectangle().fill(Color.cyan).frame(width: size/3.5, height: size/3.5).cornerRadius(2)
                    }
                }
            } else if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: fontSize))
                    .foregroundColor(.green)
            } else {
                Button(action: { viewModel.startDownload(app: app) }) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: fontSize))
                        .foregroundColor(.cyan)
                }
            }
        }
        .frame(width: isLarge ? 60 : 40, height: isLarge ? 60 : 40)
    }
}

// MARK: - Sources View
struct SourcesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var newRepoURL: String = ""
    
    var body: some View {
        ZStack {
            BlobBackgroundView()
            
            VStack(spacing: 20) {
                LiquidGlassCard {
                    VStack(spacing: 10) {
                        TextField("URL del Repositorio (https://...)", text: $newRepoURL)
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        
                        Button(action: {
                            viewModel.addSource(url: newRepoURL)
                            newRepoURL = ""
                        }) {
                            Text("Añadir Repositorio")
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(Color.cyan)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                List {
                    ForEach(viewModel.sources) { source in
                        HStack(spacing: 15) {
                            AsyncImage(url: URL(string: source.iconURL ?? "")) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Image(systemName: "server.rack").foregroundColor(.gray)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(8)
                            
                            VStack(alignment: .leading) {
                                Text(source.name)
                                    .foregroundColor(.white)
                                    .fontWeight(.bold)
                                Text(source.url)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                    .onDelete { indexSet in
                        viewModel.sources.remove(atOffsets: indexSet)
                        viewModel.fetchApps()
                    }
                }
                .hideListBackground()
            }
        }
        .navigationTitle("Fuentes")
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
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No hay archivos descargados")
                        .foregroundColor(.gray)
                }
            } else {
                List {
                    ForEach(viewModel.downloadedFiles, id: \.self) { fileURL in
                        HStack {
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 30))
                                .foregroundColor(.cyan)
                                .padding(.trailing, 8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fileURL.lastPathComponent)
                                    .foregroundColor(.white)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                                   let fileSize = attributes[.size] as? Int64 {
                                    Text(formatBytes(fileSize))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let file = viewModel.downloadedFiles[index]
                            try? FileManager.default.removeItem(at: file)
                        }
                        viewModel.refreshFilesList()
                        viewModel.checkDownloadedFiles()
                    }
                }
                .hideListBackground()
            }
        }
        .navigationTitle("Archivos")
        .onAppear {
            viewModel.refreshFilesList()
        }
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
    
    let folders = ["Documentos", "Caché"]
    
    var body: some View {
        ZStack {
            BlobBackgroundView()
            
            Form {
                Section(header: Text("Sincronización").foregroundColor(.cyan)) {
                    Toggle("Async Repo Sync", isOn: $viewModel.asyncRepoSync)
                    Toggle("Actualizar apps automáticamente", isOn: $viewModel.autoUpdateApps)
                    Toggle("Descargar solo con Wi-Fi", isOn: $viewModel.wifiOnly)
                }
                .listRowBackground(Color.white.opacity(0.08))
                
                Section(header: Text("Archivos").foregroundColor(.cyan)) {
                    Picker("Carpeta de Descargas", selection: $viewModel.downloadFolder) {
                        ForEach(folders, id: \.self) { folder in
                            Text(folder).tag(folder)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.vertical, 5)
                }
                .listRowBackground(Color.white.opacity(0.08))
                
                Section(header: Text("Apariencia").foregroundColor(.cyan)) {
                    Toggle("Modo AMOLED (Pitch Black)", isOn: $viewModel.amoledPitchBlack)
                }
                .listRowBackground(Color.white.opacity(0.08))
                
                Section(header: Text("Información").foregroundColor(.cyan)) {
                    HStack {
                        Text("Versión")
                        Spacer()
                        Text("2.1.0").foregroundColor(.gray)
                    }
                    HStack {
                        Text("Desarrollador")
                        Spacer()
                        Text("elmendezz").font(.system(.body, design: .monospaced)).foregroundColor(.cyan)
                    }
                }
                .listRowBackground(Color.white.opacity(0.08))
            }
            .hideListBackground()
        }
        .navigationTitle("Configuración")
        .onChange(of: viewModel.downloadFolder) { _ in
            // Refresca la lista de archivos y descargas cuando se cambia de directorio
            viewModel.checkDownloadedFiles()
            viewModel.refreshFilesList()
        }
    }
}

// MARK: - Liquid Glass UI Component
struct LiquidGlassCard<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    
    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .background(.ultraThinMaterial.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)]),
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ), lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.6), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Extensions
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
