import SwiftUI

// MARK: - Vista para el Diseño del Ícono de la App

/// Una vista que renderiza el diseño estático del ícono de la app,
/// basado en la animación `AnimatedRender3D` de `CreditsView.swift`.
/// Puedes usar esta vista en un simulador, tomar una captura de pantalla de alta resolución
/// y luego usarla para generar los diferentes tamaños de ícono necesarios para la App Store.
struct AppIconView: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            
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
        }
        .frame(width: 1024, height: 1024) // Tamaño estándar para el ícono de App Store Connect
    }
}

struct AppIconView_Previews: PreviewProvider {
    static var previews: some View {
        AppIconView()
            .previewLayout(.sizeThatFits)
            .padding()
    }
}

// Re-utilizamos la extensión de Color que ya tienes en SideloadApp.swift
// Si mueves AppIcon.swift a un target diferente, asegúrate de incluir esta extensión también.
/*
 extension Color { ... }
*/
