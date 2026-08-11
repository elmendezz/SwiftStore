//
//  SideloadApp.swift
//  SwiftStore
//
//  CHANGELOG:
//  - Version 1.0.1: Cambio de nombre comercial a SwiftStore, corrección de UI Liquid Glass, descarga de IPA a carpeta Downloads y vistas AMOLED.
//

import SwiftUI
import Combine

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

// MARK: - Models
struct AltStoreSource: Identifiable, Codable {
    let id: UUID
    var name: String
    var url: String
    
    init(id: UUID = UUID(), name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

struct AltStoreApp: Identifiable, Codable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let developerName: String
    let version: String
    let downloadURL: String
    let localizedDescription: String?
    let iconURL: String?
}

struct AltStoreFeed: Codable {
    let name: String
    let apps: [AltStoreApp]
}

// MARK: - View Model & Download Manager
class AppViewModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var sources: [AltStoreSource] = []
    @Published var apps: [AltStoreApp] = []
    @Published var customFonts: [String] = ["System Default", "Courier New", "Georgia", "Avenir", "Menlo"]
    @Published var selectedFont: String = "System Default"
    @Published var searchText: String = ""
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var taskAppMap: [Int: AltStoreApp] = [:]
    
    override init() {
        super.init()
        loadDefaultSources()
        fetchApps()
    }
    
    func loadDefaultSources() {
        sources = [
            AltStoreSource(name: "AltStore Official", url: "https://apps.altstore.io")
        ]
    }
    
    func addSource(name: String, url: String) {
        guard let validURL = URL(string: url), validURL.scheme != nil else { return }
        let newSource = AltStoreSource(name: name, url: url)
        sources.append(newSource)
        fetchAppsFromSource(newSource)
    }
    
    func addCustomFont(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if !customFonts.contains(name) {
            customFonts.append(name)
        }
    }
    
    func fetchApps() {
        apps.removeAll()
        for source in sources {
            fetchAppsFromSource(source)
        }
    }
    
    private func fetchAppsFromSource(_ source: AltStoreSource) {
        guard let url = URL(string: source.url) else { return }
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            if let feed = try? JSONDecoder().decode(AltStoreFeed.self, from: data) {
                DispatchQueue.main.async {
                    self.apps.append(contentsOf: feed.apps)
                }
            }
        }.resume()
    }
    
    func startDownload(app: AltStoreApp) {
        guard let url = URL(string: app.downloadURL) else { return }
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        
        let task = session.downloadTask(with: url)
        downloadTasks[app.bundleIdentifier] = task
        taskAppMap[task.taskIdentifier] = app
        
        isDownloading[app.bundleIdentifier] = true
        downloadProgress[app.bundleIdentifier] = 0.01
        
        task.resume()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let app = taskAppMap[downloadTask.taskIdentifier] else { return }
        
        let fileManager = FileManager.default
        if let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let destinationURL = downloadsDirectory.appendingPathComponent("\(app.name).ipa")
            try? fileManager.removeItem(at: destinationURL)
            do {
                try fileManager.moveItem(at: location, to: destinationURL)
            } catch {
                print("Error al guardar archivo: \(error)")
            }
        }
        
        DispatchQueue.main.async {
            self.isDownloading[app.bundleIdentifier] = false
            self.downloadProgress[app.bundleIdentifier] = 1.0
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

// MARK: - Liquid Glass UI Component
struct LiquidGlassCard<Content: View>: View {
    var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.8), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @StateObject private var viewModel = AppViewModel()
    
    var body: some View {
        TabView {
            StoreView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("Tienda", systemImage: "square.stack.3d.down.right.fill")
                }
            
            SourcesView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("Fuentes", systemImage: "link")
                }
            
            SettingsView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape.fill")
                }
            
            CreditsView()
                .tabItem {
                    Label("Créditos", systemImage: "sparkles")
                }
        }
        .accentColor(.cyan)
        .onAppear {
            UITabBar.appearance().backgroundColor = UIColor.black
            UITabBar.appearance().unselectedItemTintColor = UIColor.gray
        }
    }
}

// MARK: - Store View
struct StoreView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    var filteredApps: [AltStoreApp] {
        if viewModel.searchText.isEmpty {
            return viewModel.apps
        } else {
            return viewModel.apps.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SwiftStore")
                        .font(customFont(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Buscar aplicaciones...", text: $viewModel.searchText)
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .padding(.horizontal)
                .padding(.top)
                
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredApps) { app in
                            LiquidGlassCard {
                                HStack(spacing: 15) {
                                    RenderIconView()
                                        .frame(width: 50, height: 50)
                                        .cornerRadius(12)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.name)
                                            .font(customFont(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text(app.developerName)
                                            .font(customFont(size: 12, weight: .regular))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    DownloadButton(app: app)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    private func customFont(size: CGFloat, weight: Font.Weight) -> Font {
        if viewModel.selectedFont == "System Default" {
            return .system(size: size, weight: weight)
        } else {
            return .custom(viewModel.selectedFont, size: size)
        }
    }
}

// MARK: - App Store Style Download Button
struct DownloadButton: View {
    @EnvironmentObject var viewModel: AppViewModel
    let app: AltStoreApp
    
    var body: some View {
        let isDownloading = viewModel.isDownloading[app.bundleIdentifier] ?? false
        let progress = viewModel.downloadProgress[app.bundleIdentifier] ?? 0.0
        
        ZStack {
            if isDownloading {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(progress))
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 32, height: 32)
                        .animation(.linear(duration: 0.2), value: progress)
                    
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: 8, height: 8)
                        .cornerRadius(1)
                }
            } else {
                Button(action: {
                    viewModel.startDownload(app: app)
                }) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.cyan)
                }
            }
        }
        .frame(width: 40, height: 40)
    }
}

// MARK: - Sources View
struct SourcesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var newRepoName: String = ""
    @State private var newRepoURL: String = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Fuentes de SwiftStore")
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal)
                    .padding(.top)
                
                LiquidGlassCard {
                    VStack(spacing: 10) {
                        TextField("Nombre del Repo", text: $newRepoName)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                        
                        TextField("https://...", text: $newRepoURL)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                        
                        Button(action: {
                            viewModel.addSource(name: newRepoName, url: newRepoURL)
                            newRepoName = ""
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
                
                List {
                    ForEach(viewModel.sources) { source in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.name)
                                    .foregroundColor(.white)
                                    .fontWeight(.bold)
                                Text(source.url)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.black)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var newFontName: String = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Configuración")
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal)
                    .padding(.top)
                
                LiquidGlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Personalizar Fuentes")
                            .font(.headline)
                            .foregroundColor(.cyan)
                        
                        HStack {
                            TextField("Nombre de fuente del sistema...", text: $newFontName)
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                            
                            Button("Añadir") {
                                viewModel.addCustomFont(name: newFontName)
                                newFontName = ""
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background(Color.cyan)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                        }
                        
                        Picker("Fuente de la app", selection: $viewModel.selectedFont) {
                            ForEach(viewModel.customFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(height: 100)
                        .clipped()
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
        }
    }
}

// MARK: - Credits View & Animated Renders
struct CreditsView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Créditos")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                
                AnimatedRender3D()
                    .frame(width: 150, height: 150)
                
                LiquidGlassCard {
                    VStack(spacing: 15) {
                        Text("Desarrollado por")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("elmendezz")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        
                        Divider().background(Color.white.opacity(0.2))
                        
                        Text("Asistido por")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("Gemini")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.purple)
                    }
                    .padding()
                }
                .padding(.horizontal, 30)
            }
        }
    }
}

// MARK: - Random Geometric Render Icon
struct RenderIconView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            
            Path { path in
                path.move(to: CGPoint(x: 10, y: 10))
                path.addLine(to: CGPoint(x: 40, y: 20))
                path.addLine(to: CGPoint(x: 25, y: 45))
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.4))
            
            Circle()
                .fill(Color.cyan.opacity(0.6))
                .frame(width: 18, height: 18)
                .offset(x: 8, y: -8)
        }
    }
}

// MARK: - Animated 3D Shape Render
struct AnimatedRender3D: View {
    @State private var rotateX = 0.0
    @State private var rotateY = 0.0
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(colors: [.cyan, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 100, height: 100)
                .rotation3DEffect(.degrees(rotateX), axis: (x: 1, y: 0, z: 0))
                .rotation3DEffect(.degrees(rotateY), axis: (x: 0, y: 1, z: 0))
            
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 3)
                .frame(width: 120, height: 120)
                .rotation3DEffect(.degrees(-rotateY), axis: (x: 0, y: 1, z: 0))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                rotateX = 360
                rotateY = 180
            }
        }
    }
}
