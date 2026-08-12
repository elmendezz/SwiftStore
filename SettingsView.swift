import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var fileManager: AppFileManager
    @EnvironmentObject var viewModel: AppViewModel
    @State private var randomImageName: String = ""
    @State private var secretTapCount = 0
    @State private var showingIconExporter = false

    let renders = ["3D_Render_1", "3D_Render_2", "3D_Render_3"]
    let folders = ["Documentos", "Caché"]
    let availableLanguages: [(name: String, code: String)] = [
        ("Español", "es"),
        ("Inglés", "en"),
        ("Francés", "fr"),
        ("Alemán", "de"),
        ("Italiano", "it"),
        ("Portugués", "pt"),
        ("Japonés", "ja"),
        ("Chino (Simplificado)", "zh-Hans")
    ]

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
        return "SwiftStore v\(version)"
    }

    var body: some View {
        ZStack {
            BlobBackgroundView()

            Form {
                Section(header: Text("Sincronización").foregroundColor(.cyan)) {
                    Toggle("Sincronización asíncrona de repos", isOn: $viewModel.asyncRepoSync).toggleStyle(SwitchToggleStyle(tint: .cyan))
                    
                    Toggle("Refrescar apps automáticamente", isOn: $viewModel.enableAutoRefresh)
                        .toggleStyle(SwitchToggleStyle(tint: .cyan))

                    if viewModel.enableAutoRefresh {
                        Picker("Intervalo de refresco", selection: $viewModel.autoRefreshInterval) {
                            Text("5 minutos").tag(5.0)
                            Text("15 minutos").tag(15.0)
                            Text("30 minutos").tag(30.0)
                            Text("1 hora").tag(60.0)
                        }
                    }
                }.listRowBackground(Color.white.opacity(0.08))

                Section(header: Text("Archivos").foregroundColor(.cyan)) {
                    Picker("Carpeta de Descargas", selection: $viewModel.downloadFolder) {
                        ForEach(folders, id: \.self) { folder in Text(folder).tag(folder) }
                    }
                    .pickerStyle(SegmentedPickerStyle()).padding(.vertical, 5)
                    .onChange(of: viewModel.downloadFolder) { newValue in
                        fileManager.downloadFolder = newValue
                    }
                }.listRowBackground(Color.white.opacity(0.08))

                Section(header: Text("Traducción").foregroundColor(.cyan)) {
                    Toggle("Traducir descripciones", isOn: $viewModel.enableTranslation).toggleStyle(SwitchToggleStyle(tint: .cyan))
                    Picker("Idioma De La Traducción", selection: $viewModel.translationLanguageCode) {
                        ForEach(availableLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .disabled(!viewModel.enableTranslation)
                }.listRowBackground(Color.white.opacity(0.08))

                Section(header: Text("Apariencia").foregroundColor(.cyan)) {
                    Toggle("Modo AMOLED (Pitch Black)", isOn: $viewModel.amoledPitchBlack).toggleStyle(SwitchToggleStyle(tint: .cyan))
                    Toggle("Fondo Animado (Burbujas)", isOn: $viewModel.enableAnimatedBackground).toggleStyle(SwitchToggleStyle(tint: .cyan))
                    Toggle("Efecto Glow en Créditos", isOn: $viewModel.enableCreditsGlow).toggleStyle(SwitchToggleStyle(tint: .cyan))
                }.listRowBackground(Color.white.opacity(0.08))
                .onTapGesture {
                    secretTapCount += 1
                    if secretTapCount >= 5 {
                        showingIconExporter = true
                    }
                }

                Section(header: Text("Acerca de").foregroundColor(.cyan)) {
                    VStack(alignment: .center, spacing: 10) {
                        Image(randomImageName.isEmpty ? "default_render" : randomImageName)
                            .resizable().aspectRatio(contentMode: .fit).frame(height: 120).cornerRadius(15)
                            .onAppear { randomImageName = renders.randomElement() ?? "" }
                        Text(appVersion).font(.headline).foregroundColor(.white)
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
        .sheet(isPresented: $showingIconExporter) {
            AppIconExporterView()
                .onDisappear { secretTapCount = 0 } // Reset when sheet is dismissed
                .background(Color.black.ignoresSafeArea())
        }
    }
}