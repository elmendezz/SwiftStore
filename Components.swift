import SwiftUI
import Combine

// MARK: - Animated Liquid Blob Background

struct BlobBackgroundView: View {
    @AppStorage("enableAnimatedBackground")
    var enableAnimatedBackground: Bool = true
    
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if enableAnimatedBackground {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#3E3564"), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 600, height: 600)
                    .rotationEffect(.degrees(rotation))
                    .offset(y: -300)
                    .opacity(0.5)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 80).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}


// MARK: - Organic Blob Shape
struct BlobShape: Shape {

    let points: Int
    let amplitude: CGFloat
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {

        let center = CGPoint(
            x: rect.midX,
            y: rect.midY
        )

        let radius = min(
            rect.width,
            rect.height
        ) / 2

        var path = Path()

        var coordinates: [CGPoint] = []

        for i in 0..<points {

            let angle =
                (CGFloat(i) / CGFloat(points)) *
                CGFloat.pi * 2

            // Variación orgánica de la forma
            let wave1 = sin(angle * 3 + phase) * amplitude
            let wave2 = cos(angle * 2 - phase * 0.7) * amplitude * 0.55
            let wave3 = sin(angle * 5 + phase * 0.4) * amplitude * 0.25

            let variation =
                1.0 +
                wave1 +
                wave2 +
                wave3

            let r = radius * variation

            coordinates.append(
                CGPoint(
                    x: center.x + cos(angle) * r,
                    y: center.y + sin(angle) * r
                )
            )
        }

        guard let first = coordinates.first else {
            return path
        }

        path.move(to: first)

        // Curvas suaves entre puntos
        for i in 0..<coordinates.count {

            let current = coordinates[i]

            let next =
                coordinates[
                    (i + 1) % coordinates.count
                ]

            let nextNext =
                coordinates[
                    (i + 2) % coordinates.count
                ]

            let control1 = CGPoint(
                x: current.x + (next.x - current.x) * 0.45,
                y: current.y + (next.y - current.y) * 0.45
            )

            let control2 = CGPoint(
                x: next.x - (nextNext.x - next.x) * 0.20,
                y: next.y - (nextNext.y - next.y) * 0.20
            )

            path.addCurve(
                to: next,
                control1: control1,
                control2: control2
            )
        }

        path.closeSubpath()

        return path
    }
}

// MARK: - Sistema de Caché de Imágenes

/// Un gestor de caché simple para almacenar y recuperar datos de imágenes en disco.
class ImageCache {
    static let shared = ImageCache()
    private let fileManager = FileManager.default
    private lazy var cacheDirectory: URL = {
        let url = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheUrl = url.appendingPathComponent("ImageCache")
        try? fileManager.createDirectory(at: cacheUrl, withIntermediateDirectories: true, attributes: nil)
        return cacheUrl
    }()

    private func path(for key: String) -> URL {
        let fileName = Data(key.utf8).base64EncodedString()
        return cacheDirectory.appendingPathComponent(fileName)
    }

    func set(data: Data, for key: String) {
        let url = path(for: key)
        try? data.write(to: url)
    }

    func get(for key: String) -> Data? {
        let url = path(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    func clear() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil, options: [])
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
            print("ImageCache cleared successfully.")
        } catch {
            print("Error clearing image cache: \(error)")
        }
    }
}

/// Una vista que carga una imagen desde una URL, usando una caché en disco para evitar descargas repetidas.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var image: Image?

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                content(image)
            } else {
                placeholder()
            }
        }
        .onAppear(perform: loadImage)
    }

    private func loadImage() {
        guard let url = url else { return }
        let key = url.absoluteString

        // 1. Intentar cargar desde la caché
        if let cachedData = ImageCache.shared.get(for: key), let uiImage = UIImage(data: cachedData) {
            self.image = Image(uiImage: uiImage)
            return
        }

        // 2. Si no está en caché, descargar
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let uiImage = UIImage(data: data) else { return }
            
            // 3. Guardar en caché y actualizar la UI
            ImageCache.shared.set(data: data, for: key)
            DispatchQueue.main.async {
                self.image = Image(uiImage: uiImage)
            }
        }.resume()
    }
}

// MARK: - Observador de Velocidad de Scroll
class ScrollObserver: ObservableObject {
    @Published var scrollVelocity: CGFloat = 0
    private var lastOffset: CGFloat = 0

    func updateVelocity(from offset: CGFloat) {
        let velocity = offset - lastOffset
        // Usamos una animación para suavizar el cambio de velocidad
        withAnimation(.easeOut(duration: 0.1)) {
            self.scrollVelocity = velocity
        }
        self.lastOffset = offset
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Liquid Glass Component & Colors
struct LiquidGlassCard<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding().background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)).background(.ultraThinMaterial.opacity(0.3)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)))
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4) // Sombra más ligera para mejorar el rendimiento en listas largas
    }
}

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

extension View {
    /// Aplica un modificador condicionalmente.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}