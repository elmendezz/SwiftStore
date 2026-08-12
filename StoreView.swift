import SwiftUI
import Translation

// MARK: - Store View
struct StoreView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var sourceManager: SourceManager
    @EnvironmentObject var scrollObserver: ScrollObserver
    
    var filteredApps: [AltStoreApp] {
        let apps = sourceManager.apps
        return viewModel.searchText.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
    }
    
    var body: some View {
        ScrollViewReader { proxy in // Permite el scroll programático
            ZStack {
                BlobBackgroundView()

                ScrollView {
                    VStack(spacing: 15) {
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
                            }.padding(.horizontal).padding(.bottom, 20)
                        }
                    }
                }
                .background(
                    // Observador de scroll simplificado
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: scrollObserver.updateVelocity(from:))
        }
        .searchable(text: $viewModel.searchText, prompt: "Buscar aplicaciones...")
        .navigationTitle("SwiftStore")
    }
}

// MARK: - Components (Card & Detail)
struct AppCardView: View {
    let app: AltStoreApp
    var body: some View {
        LiquidGlassCard {
            HStack(spacing: 15) {
                CachedAsyncImage(url: URL(string: app.iconURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 15).fill(Color.black.opacity(0.8)) // Placeholder mejorado
                }
                .frame(width: 60, height: 60) // Tamaño ligeramente más grande
                .background(Color.black.opacity(0.8))
                .cornerRadius(15) // Radio de esquina ajustado
                
                VStack(alignment: .leading, spacing: 2) { // Espaciado reducido
                    Text(app.name).font(.headline.bold()).foregroundColor(.white) // Fuente semántica
                    Text(app.developerName).font(.subheadline).foregroundColor(.gray) // Fuente semántica
                    
                    Text("v\(app.version)") // Añadida la versión de la app
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let description = app.localizedDescription, !description.isEmpty {
                        TranslatedText(description)
                            .font(.caption).foregroundColor(.secondary) // Usando secondary para mejor contraste
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                }
                Spacer()
                DownloadIndicator(app: app)
            }
        }.padding(.horizontal)
    }
}

struct AppDetailView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var fileManager: AppFileManager
    let app: AltStoreApp
    var body: some View {
        ZStack {
            BlobBackgroundView()
            ScrollView {
                VStack(spacing: 20) {
                    CachedAsyncImage(url: URL(string: app.iconURL ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.8))
                    }.frame(width: 120, height: 120).cornerRadius(24).shadow(radius: 10)
                    
                    Text(app.name).font(.largeTitle).bold().foregroundColor(.white)
                    Text(app.version).font(.subheadline).foregroundColor(.cyan)
                    DownloadIndicator(app: app, isLarge: true)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Descripción").font(.headline).foregroundColor(.white)
                        TranslatedText(app.localizedDescription ?? "No hay descripción disponible.")
                            .foregroundColor(.gray).font(.body)
                    }.padding().background(Color.white.opacity(0.05)).cornerRadius(16).padding(.horizontal)
                }.padding(.vertical)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { fileManager.deleteAppFile(app: app); downloadManager.startDownload(app: app) }) { Label("Volver a descargar", systemImage: "arrow.clockwise.icloud") }
                    Button(action: { fileManager.deleteAppFile(app: app) }) { Label("Eliminar", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").foregroundColor(.white).font(.headline) } // Icono nativo de 3 puntos
            }
        }
    }
}

/// Una vista que muestra texto, traduciéndolo automáticamente si la opción está activada en los ajustes.
/// Utiliza la API `TranslationSession` de iOS 16+. En versiones anteriores, muestra el texto original.
struct TranslatedText: View {
    let originalText: String
    
    @EnvironmentObject var viewModel: AppViewModel
    @State private var translatedText: String?
    
    init(_ text: String) {
        self.originalText = text
    }

    var body: some View {
        let textToDisplay = (viewModel.enableTranslation ? translatedText : originalText) ?? originalText
        
        Text(textToDisplay)
            .task(id: viewModel.enableTranslation) {
                await performTranslation()
            }
            .task(id: viewModel.translationLanguageCode) {
                await performTranslation()
            }
    }
    
    private func performTranslation() async {
        // Si la traducción está desactivada o el texto está vacío, reseteamos.
        guard viewModel.enableTranslation, !originalText.isEmpty else {
            if translatedText != nil {
                translatedText = nil
            }
            return
        }
        
        // La API de sesión de traducción solo está disponible en iOS 16+
        if #available(iOS 16.0, *) {
            do {                
                let targetLanguage = Locale.Language(identifier: viewModel.translationLanguageCode)
                
                // Para iOS 16.0 y superiores, usamos TranslationSession.
                // Se inicializa sin parámetros y luego se configura.
                let session = TranslationSession()
                try await session.prepare(for: .init(source: .autodetected, target: targetLanguage))
                let response = try await session.translate(originalText)
                translatedText = response.translation
            } catch {
                translatedText = nil // Si falla, volvemos al texto original.
            }
        }
    }
}

// MARK: - Download Indicator
struct DownloadIndicator: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var fileManager: AppFileManager
    let app: AltStoreApp
    var isLarge: Bool = false
    
    var body: some View {
        let isDownloading = downloadManager.isDownloading[app.bundleIdentifier] ?? false
        let isQueued = downloadManager.downloadQueue.contains(app)
        let progress = downloadManager.downloadProgress[app.bundleIdentifier] ?? 0.0
        let isDownloaded = fileManager.downloadedApps.contains(app.bundleIdentifier)
        
        let size: CGFloat = isLarge ? 50 : 32
        let fontSize: CGFloat = isLarge ? 30 : 28
        
        ZStack {
            if isDownloading {
                Button(action: { downloadManager.cancelDownload(app: app) }) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 3).frame(width: size, height: size)
                        Circle().trim(from: 0.0, to: CGFloat(progress)).stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: size, height: size)
                        Rectangle().fill(Color.cyan).frame(width: size/3.5, height: size/3.5).cornerRadius(2)
                    }
                }
            } else if isQueued {
                Button(action: { downloadManager.cancelDownload(app: app) }) {
                    Image(systemName: "clock.fill").font(.system(size: fontSize)).foregroundColor(.orange)
                }
            } else if isDownloaded {
                Image(systemName: "checkmark.circle.fill").font(.system(size: fontSize)).foregroundColor(.green)
            } else {
                Button(action: { downloadManager.startDownload(app: app) }) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: fontSize)).foregroundColor(.cyan)
                }
            }
        }.frame(width: isLarge ? 60 : 40, height: isLarge ? 60 : 40)
    }
}