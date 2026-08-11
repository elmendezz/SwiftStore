import SwiftUI

// MARK: - Credits View & Animated Renders
struct CreditsView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Créditos")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                
                AnimatedRender3D()
                    .frame(width: 150, height: 150)
                
                LiquidGlassCard {
                    VStack(spacing: 15) {
                        Text("Desarrollado por")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("elmendezz")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        
                        Divider().background(Color.white.opacity(0.2))
                        
                        Text("Asistido por")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("Gemini")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.purple)
                    }
                    .padding()
                }
                .padding(.horizontal, 30)
            }
        }
    }
}

// Animación de Formas Aleatorias para la Vista de Créditos
struct AnimatedRender3D: View {
    @State private var phase: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                .frame(width: 100, height: 100)
                .offset(x: sin(phase) * 30, y: cos(phase) * 30)
                .shadow(color: .cyan.opacity(0.5), radius: 10)
            
            RoundedRectangle(cornerRadius: 25)
                .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(phase * 60))
                .offset(x: cos(phase * 1.5) * -40, y: sin(phase * 0.8) * 40)
                .shadow(color: .purple.opacity(0.5), radius: 10)
            
            Capsule()
                .fill(LinearGradient(colors: [.orange, .pink], startPoint: .bottomLeading, endPoint: .topTrailing))
                .frame(width: 120, height: 50)
                .rotationEffect(.degrees(-phase * 45))
                .offset(x: sin(phase * 1.2) * 20, y: cos(phase * 1.5) * -40)
                .shadow(color: .pink.opacity(0.5), radius: 10)
        }
        .blur(radius: 2)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }
}
