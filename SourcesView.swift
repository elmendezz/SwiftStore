import SwiftUI
import Components // Importamos el nuevo archivo de componentes

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