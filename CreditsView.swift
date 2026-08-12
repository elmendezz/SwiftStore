//
//  CreditsView.swift
//  SwiftStore
//
//  Version: 1.4
//  Changelog:
//  - Version 1.0: Vista inicial de créditos con Render 3D animado.
//  - Version 1.1: Removido crédito de asistencia de IA, añadida sección de información de la app, estado de licencia, estadísticas de sesión y botones de interacción social manteniendo intacta la animación 3D.
//  - Version 1.2: Removidas métricas y botones extra. Añadidos links a GitHub y App (placeholder), acordeón vertical en gris y selector modal para licencias.
//  - Version 1.3: Removida la sección de información del sistema. Reposicionada la tarjeta de desarrollado por elmendezz al fondo cerca del dock sin fondo, con el mismo tamaño y estilo de los enlaces directos.
//  - Version 1.4: Fijados todos los textos y elementos del pie de página para garantizar que permanezcan 100% estáticos sin transiciones ni animaciones. Render 3D animado intacto.
//

import SwiftUI

// MARK: - Tipos de Animación para Créditos
enum AnimationType: String, CaseIterable, Identifiable {
    case original = "Original"
    case gemini = "Gemini"
    var id: String { self.rawValue }
}

struct CreditsView: View {
    @State private var showingLicensesSheet = false
    @State private var elmendezzTapCount = 0
    @State private var showingAnimationPicker = false
    @AppStorage("creditsAnimation") private var selectedAnimation: AnimationType = .original
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Render 3D exactamente igual e intacto
                Group {
                    switch selectedAnimation {
                    case .original: AnimatedRender3D()
                    case .gemini: GeminiLogoAnimation()
                    }
                }.frame(width: 150, height: 150)
                
                Spacer()
                
                // Sección inferior fija y estática cerca del dock
                VStack(spacing: 14) {
                    // Texto Desarrollado por elmendezz
                    HStack(spacing: 6) {
                        Text("Desarrollado por")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gray)
                        
                        Text("elmendezz")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    .onTapGesture {
                        elmendezzTapCount += 1
                        if elmendezzTapCount >= 5 {
                            showingAnimationPicker = true
                            elmendezzTapCount = 0
                        }
                    }
                    
                    // Enlaces directos estáticos
                    Link(destination: URL(string: "https://github.com/elmendezz")!) {
                        HStack {
                            Image("github_icon") // Usando el icono personalizado
                            Text("@elmendezz")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    }
                    
                    Link(destination: URL(string: "https://github.com/elmendezz/SwiftStore")!) {
                        HStack {
                            Image(systemName: "app.fill")
                            Text("SwiftStore")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.cyan)
                    }
                    
                    Button(action: {
                        showingLicensesSheet.toggle()
                    }) {
                        Text("Licencias")
                            .font(.caption)
                            .underline()
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 20)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .sheet(isPresented: $showingLicensesSheet) {
            LicensesView()
        }
        .actionSheet(isPresented: $showingAnimationPicker) {
            ActionSheet(
                title: Text("Seleccionar Animación"),
                message: Text("Elige una animación para la vista de créditos."),
                buttons: AnimationType.allCases.map { animationType in
                        .default(Text(animationType.rawValue)) { selectedAnimation = animationType }
                } + [.cancel()]
            )
        }
    }
}

// MARK: - Licencias Sheet View
struct LicensesView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        LicenseCard(title: "SwiftStore", bodyText: "Copyright (c) 2026 elmendezz.\nTodos los derechos reservados.")
                        LicenseCard(title: "SwiftUI & Apple SDKs", bodyText: "Proporcionado por Apple Inc. bajo los términos de desarrollador de Apple.")
                        LicenseCard(title: "Open Source Components", bodyText: "Uso de licencias MIT / Apache 2.0 para dependencias internas.")
                    }
                    .padding()
                }
            }
            .navigationTitle("Licencias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

// MARK: - Icono de GitHub (Recreación simple)
struct GitHubIcon: View {
    var body: some View {
        ZStack {
            // Cuerpo del Octocat
            Path { path in
                path.move(to: CGPoint(x: 15, y: 0))
                path.addQuadCurve(to: CGPoint(x: 0, y: 15), control: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 15, y: 30), control: CGPoint(x: 0, y: 30))
                path.addQuadCurve(to: CGPoint(x: 30, y: 15), control: CGPoint(x: 30, y: 30))
                path.addQuadCurve(to: CGPoint(x: 15, y: 0), control: CGPoint(x: 30, y: 0))
            }
            .fill(Color.white)
            
            // Ojos
            Circle().fill(Color.black).frame(width: 3, height: 3).offset(x: -5, y: -3)
            Circle().fill(Color.black).frame(width: 3, height: 3).offset(x: 5, y: -3)
        }
        .frame(width: 16, height: 16) // Tamaño similar a un SF Symbol
    }
}

// MARK: - Animación del Logo de Gemini
struct GeminiLogoAnimation: View {
    @State private var phase: Double = 0
    
    var body: some View {
        ZStack {
            // Estrella principal
            Image(systemName: "star.fill")
                .font(.system(size: 80))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "4285F4"), Color(hex: "9B72CB")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .rotationEffect(.degrees(phase * 20))
                .scaleEffect(1 + sin(phase * 1.5) * 0.1)

            // Estrella secundaria
            Image(systemName: "sparkle")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "9B72CB"), Color(hex: "F4B400")], startPoint: .top, endPoint: .bottom))
                .rotationEffect(.degrees(-phase * 30))
                .offset(x: cos(phase) * 40, y: sin(phase) * 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { phase = .pi * 2 }
        }
    }
}

struct LicenseCard: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(bodyText)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }
}

// MARK: - Animación de Formas Aleatorias para la Vista de Créditos (INTACTO)
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
