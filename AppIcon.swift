import SwiftUI

// MARK: - Vista de Exportación de Íconos

/// Una vista que permite al usuario seleccionar un tamaño y exportar el ícono de la app.
struct AppIconExporterView: View {
    @State private var selectedSize: CGFloat = 1024.0
    private let iconSizes: [CGFloat] = [1024, 512, 180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20]

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Vista previa del ícono
                AppIconView(size: selectedSize)
                    .frame(width: 256, height: 256) // Tamaño de previsualización fijo
                    .clipShape(RoundedRectangle(cornerRadius: 256 * 0.22, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 15, y: 5)
                    .padding(.top, 20)

                // Selector de tamaño
                Picker("Tamaño de Exportación", selection: $selectedSize) {
                    ForEach(iconSizes, id: \.self) { size in
                        Text("\(Int(size)) x \(Int(size)) px").tag(size)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .padding(.horizontal)

                // Botón de exportación con compatibilidad para iOS 15
                if #available(iOS 16.0, *) {
                    ShareLink(
                        item: renderToImage(),
                        preview: SharePreview("AppIcon-\(Int(selectedSize)).png", image: renderToImage())
                    ) {
                        exportButtonLabel()
                    }
                } else {
                    // Fallback para iOS 15
                    Button(action: {
                        // La funcionalidad de compartir en iOS 15 es más limitada
                        // y requiere UIViewControllerRepresentable para compartir una imagen.
                        // Por simplicidad, aquí solo imprimimos un mensaje.
                        // Para una implementación completa, se necesitaría un `UIActivityViewController`.
                        print("La exportación avanzada solo está disponible en iOS 16+.")
                    }) {
                        exportButtonLabel()
                    }
                }
                .padding()

                Spacer()
            }
            .navigationTitle("Exportar Ícono")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.black.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
    }

    /// Etiqueta reutilizable para el botón de exportación.
    @ViewBuilder
    private func exportButtonLabel() -> some View {
        Label("Exportar Imagen", systemImage: "square.and.arrow.up")
            .font(.headline.weight(.bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.cyan)
            .cornerRadius(12)
    }

    /// Renderiza la `AppIconView` a una imagen `Image` para poder compartirla (iOS 16+).
    @available(iOS 16.0, *)
    private func renderToImage() -> Image {
        let viewToRender = AppIconView(size: selectedSize)
        let renderer = ImageRenderer(content: viewToRender)
        renderer.scale = UIScreen.main.scale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        // Fallback a una imagen vacía si la renderización falla
        return Image(systemName: "exclamationmark.triangle")
    }
}

/// Una vista que renderiza el diseño estático del ícono de la app,
/// basado en la animación `AnimatedRender3D` de `CreditsView.swift`.
struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Fondo del ícono (Squircle)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "1C1C1E"), .black], startPoint: .top, endPoint: .bottom))

            // Formas basadas en AnimatedRender3D
            ZStack {
                // Círculo (Base)
                Circle()
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.5, height: size * 0.5)
                    .shadow(color: .black.opacity(0.3), radius: size * 0.05, y: size * 0.02)
                    .rotationEffect(.degrees(15))
                    .offset(x: size * -0.1, y: size * 0.1)

                // Rectángulo Redondeado (Medio)
                RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                    .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.55, height: size * 0.55)
                    .shadow(color: .black.opacity(0.3), radius: size * 0.05, y: size * 0.02)
                    .rotationEffect(.degrees(-25))

                // Cápsula (Frente)
                Capsule()
                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .bottomLeading, endPoint: .topTrailing))
                    .frame(width: size * 0.6, height: size * 0.28)
                    .shadow(color: .black.opacity(0.3), radius: size * 0.05, y: size * 0.02)
                    .rotationEffect(.degrees(20))
                    .offset(x: size * 0.1, y: size * -0.15)
            }
        }
        .frame(width: size, height: size)
    }
}

struct AppIconView_Previews: PreviewProvider {
    static var previews: some View {
        AppIconExporterView()
    }
}

// Re-utilizamos la extensión de Color que ya tienes en SideloadApp.swift
// Si mueves AppIcon.swift a un target diferente, asegúrate de incluir esta extensión también.
/*
 extension Color { ... }
*/
