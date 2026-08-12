//
//  CreditsView.swift
//  SwiftStore
//
//  Version: 1.3
//  Changelog:
//  - Version 1.0: Vista inicial de créditos con Render 3D animado.
//  - Version 1.1: Removido crédito de asistencia de IA, añadida sección de información de la app, estado de licencia, estadísticas de sesión y botones de interacción social manteniendo intacta la animación 3D.
//  - Version 1.2: Removidas métricas y botones extra. Añadidos links a GitHub y App (placeholder), acordeón vertical en gris y selector modal para licencias.
//  - Version 1.3: Removida información del sistema. Tarjeta de desarrollador movida al fondo en estilo transparente/plano. Añadido Easter Egg de 5 toques en "elmendezz" para cambiar la animación del render 3D (Aleatorio, Logo Gemini, Esfera Fluida).
//

import SwiftUI

enum AnimationType: String, CaseIterable, Identifiable {
    case random = "Aleatorio (Original)"
    case gemini = "Logo Gemini"
    case fluidSphere = "Esfera Fluida"
    
    var id: String { self.rawValue }
}

struct CreditsView: View {
    @State private var showingLicensesSheet = false
    @State private var showingAnimationSelector = false
    @State private var developerTapCount = 0
    @State private var selectedAnimation: AnimationType = .random

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 25) {
                    Text("Créditos")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    // Render 3D dinámico según selección
                    Render3DContainer(animationType: selectedAnimation)
                        .frame(width: 150, height: 150)
                    
                    // Links directos
                    VStack(spacing: 12) {
                        Link(destination: URL(string: "https://github.com/elmendezz")!) {
                            HStack {
                                Image(systemName: "code")
                                Text("GitHub: @elmendezz")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        }
                        
                        Link(destination: URL(string: "https://github.com/elmendezz/SwiftStore")!) {
                            HStack {
                                Image(systemName: "app.fill")
                                Text("App SwiftStore")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.cyan)
                        }
                        
                        Button(action: {
                            showingLicensesSheet.toggle()
                        }) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                Text("Licencias")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer(minLength: 30)
                    
                    // Desarrollado por al final (Sin fondo, mismo tamaño visual de links + Easter Egg 5 taps)
                    VStack(spacing: 4) {
                        Text("Desarrollado por")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("elmendezz")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.cyan)
                            .onTapGesture {
                                developerTapCount += 1
                                if developerTapCount >= 5 {
                                    developerTapCount = 0
                                    showingAnimationSelector = true
                                }
                            }
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .sheet(isPresented: $showingLicensesSheet) {
            LicensesView()
        }
        .confirmationDialog("Seleccionar Animación 3D", isPresented: $showingAnimationSelector, titleVisibility: .visible) {
            ForEach(AnimationType.allCases) { type in
                Button(type.rawValue) {
                    selectedAnimation = type
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// MARK: - Contenedor de Animaciones
struct Render3DContainer: View {
    let animationType: AnimationType

    var body: some View {
        Group {
            switch animationType {
            case .random:
                AnimatedRender3D()
            case .gemini:
                GeminiLogoRender()
            case .fluidSphere:
                FluidSphereRender()
            }
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

// MARK: - Animación 1: Formas Aleatorias (INTACTO)
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

// MARK: - Animación 2: Logo Estilo Gemini (Sparkle / Starburst Neon)
struct GeminiLogoRender: View {
    @State private var pulse: CGFloat = 1.0
    @State private var rotate: Double = 0
    
    var body: some View {
        ZStack {
            // Destello central Neón tipo Gemini
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple, .cyan, .white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(pulse)
                .rotationEffect(.degrees(rotate))
                .shadow(color: .cyan.opacity(0.8), radius: 15)
                .shadow(color: .purple.opacity(0.6), radius: 25)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulse = 1.15
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                rotate = 360
            }
        }
    }
}

// MARK: - Animación 3: Esfera Fluida
struct FluidSphereRender: View {
    @State private var scale: CGFloat = 0.8
    @State private var hueRotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.cyan, .blue, .purple, .black],
                        center: .center,
                        startRadius: 10,
                        endRadius: 75
                    )
                )
                .scaleEffect(scale)
                .hueRotation(.degrees(hueRotation))
                .blur(radius: 4)
                .shadow(color: .blue.opacity(0.7), radius: 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                scale = 1.1
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                hueRotation = 360
            }
        }
    }
}
