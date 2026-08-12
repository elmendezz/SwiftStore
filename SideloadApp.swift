import SwiftUI
import Combine

// MARK: - App Entry Point
@main
struct SwiftStoreApp: App {
    @StateObject private var sourceManager = SourceManager()
    @StateObject private var fileManager: AppFileManager
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var viewModel = AppViewModel()

    init() {
        let initialFolder = UserDefaults.standard.string(forKey: "downloadFolder") ?? "Documentos"
        let fm = AppFileManager(initialDownloadFolder: initialFolder)
        _fileManager = StateObject(wrappedValue: fm)
        _downloadManager = StateObject(wrappedValue: DownloadManager(fileManager: fm))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
                .environmentObject(sourceManager)
                .environmentObject(downloadManager)
                .environmentObject(fileManager)
                .environmentObject(viewModel)
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

// MARK: - Main View Model (Facade)
class AppViewModel: ObservableObject {
    // MARK: Settings (@AppStorage)
    @AppStorage("asyncRepoSync") var asyncRepoSync: Bool = true
    @AppStorage("enableAutoRefresh") var enableAutoRefresh: Bool = false
    @AppStorage("autoRefreshInterval") var autoRefreshInterval: Double = 15.0 // en minutos
    @AppStorage("wifiOnly") var wifiOnly: Bool = true // Nota: Esta opción no está implementada actualmente.
    @AppStorage("amoledPitchBlack") var amoledPitchBlack: Bool = true
    @AppStorage("downloadFolder") var downloadFolder: String = "Documentos" // This now drives the UI in SettingsView
    @AppStorage("enableAnimatedBackground") var enableAnimatedBackground: Bool = true
    @AppStorage("enableCreditsGlow") var enableCreditsGlow: Bool = false

    // MARK: UI State
    @Published var searchText: String = ""
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var sourceManager: SourceManager
    @EnvironmentObject var viewModel: AppViewModel
    @StateObject private var scrollObserver = ScrollObserver()
    @State private var tabSelection: Int = 0
    @State private var storeViewId = UUID() // Para hacer pop-to-root en la vista de la tienda
    @State private var showingLogView = false
    @State private var autoRefreshCancellable: AnyCancellable?

    // Binding personalizado para detectar toques en la pestaña ya seleccionada.
    private var selectedTab: Binding<Int> {
        Binding(
            get: { tabSelection },
            set: { newValue in
                if newValue == tabSelection {
                    // Si el usuario toca la misma pestaña, hacemos pop-to-root.
                    // Implementado para la pestaña de la tienda.
                    if newValue == 0 {
                        storeViewId = UUID()
                    }
                }
                tabSelection = newValue
            }
        )
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: selectedTab) { // Usamos el binding personalizado
                NavigationView { StoreView() }
                    .id(storeViewId) // ID para forzar la recreación de la vista
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Tienda", systemImage: "square.stack.3d.down.right.fill") }
                    .tag(0)
                
                NavigationView { SourcesView() }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Fuentes", systemImage: "link") }
                    .tag(1)
                
                NavigationView { FilesView() }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Archivos", systemImage: "folder.fill") }
                    .tag(2)
                
                NavigationView { SettingsView() }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
                    .tag(3)
            }
            .accentColor(.cyan)
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 15.0, *) { UITabBar.appearance().scrollEdgeAppearance = appearance }
            }
            .onShake {
                if !sourceManager.recentlyDeletedSources.isEmpty {
                    sourceManager.showUndoAlert = true
                }
            }
            .alert(isPresented: $sourceManager.showUndoAlert) {
                Alert(
                    title: Text("Deshacer acción"),
                    message: Text("¿Deseas restaurar las fuentes eliminadas recientemente?"),
                    primaryButton: .default(Text("Deshacer")) { sourceManager.undoDelete() },
                    secondaryButton: .cancel()
                )
            }
            
            if sourceManager.isUpdatingRepos {
                Button(action: { showingLogView = true }) {
                    LiveStatusOverlay(status: sourceManager.repoUpdateStatus, progress: sourceManager.repoDownloadProgress)
                }
                .buttonStyle(PlainButtonStyle()) // Evita que el botón altere el estilo del overlay.
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
                .padding(.bottom, 60)
            }
        }
        .sheet(isPresented: $showingLogView) {
            ActivityLogView()
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
