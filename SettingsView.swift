import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var randomImageName: String = ""
    @State private var secretTapCount = 0
    @State private var showingIconExporter = false

    let renders = ["3D_Render_1", "3D_Render_2", "3D_Render_3"]
    let folders = ["Documentos", "Caché"]

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
        return "SwiftStore v\(version)"
    }

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