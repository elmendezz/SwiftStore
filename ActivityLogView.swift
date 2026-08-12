import SwiftUI

/// Una vista que muestra un registro en tiempo real de las operaciones de red del AppViewModel.
struct ActivityLogView: View {
    @EnvironmentObject var sourceManager: SourceManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                // Reutilizamos el fondo animado para consistencia visual.
                BlobBackgroundView()
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(sourceManager.activityLog.indices, id: \.self) { index in
                                Text(sourceManager.activityLog[index])
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                    .id(index)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: sourceManager.activityLog) { _ in
                        // Asegura que la vista siempre muestre el último registro.
                        if let lastIndex = sourceManager.activityLog.indices.last {
                            withAnimation {
                                proxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Registro de Actividad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Limpiar") {
                        sourceManager.activityLog.removeAll()
                    }
                    .foregroundColor(.cyan)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
            }
        }
    }
}