//
//  CreditsView.swift
//  SwiftStore
//
//  Version: 1.3
//  Changelog:
//  - Version 1.0: Vista inicial de créditos con Render 3D animado.
//  - Version 1.1: Removido crédito de asistencia de IA, añadida sección de información de la app, estado de licencia, estadísticas de sesión y botones de interacción social manteniendo intacta la animación 3D.
//  - Version 1.2: Removidas métricas y botones extra. Añadidos links a GitHub y App (placeholder), acordeón vertical en gris y selector modal para licencias.
//  - Version 1.3: Removida la sección de información del sistema. Reposicionada la tarjeta de desarrollador hacia la parte inferior sin fondo, ajustada al mismo ancho de los botones de GitHub y colocada cerca de la parte inferior.
//

import SwiftUI

struct CreditsView: View {
    @State private var showingLicensesSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Text("Créditos")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                Spacer()
                
                // Render 3D exactamente igual e intacto
                AnimatedRender3D()
                    .frame(width: 150, height: 150)
                
                Spacer()
                
                // Sección inferior agrupada cerca del dock/bottom
                VStack(spacing: 16) {
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
                            Text("Licencias")
                                .font(.subheadline.weight(.medium))
                                .underline()
                                .foregroundColor(.cyan)
                        }
                    }
                    
                    // Tarjeta de Desarrollador (sin fondo, tamaño alineado con los links)
                    VStack(spacing: 4) {
                        Text("Desarrollado por")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("elmendezz")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showingLicensesSheet) {
            LicensesView()
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
