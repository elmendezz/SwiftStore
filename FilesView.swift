import SwiftUI
import Components // Importamos el nuevo archivo de componentes

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