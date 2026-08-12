# SwiftStore
<img width="1280" height="640" alt="IMG_2690" src="https://github.com/user-attachments/assets/9db5ab0d-eed2-42f4-808c-937f70b5b79e" />

[![SwiftUI](https://img.shields.io/badge/Hecho%20con-SwiftUI-cyan.svg)](https://developer.apple.com/xcode/swiftui/)
[![iOS](https://img.shields.io/badge/iOS-16.0%2B-blue.svg)](https://www.apple.com/ios/)
[![Build](https://github.com/elmendezz/SwiftStore/actions/workflows/build.yml/badge.svg)](https://github.com/elmendezz/SwiftStore/actions/workflows/build.yml)

**SwiftStore** es un cliente alternativo moderno y ligero para explorar repositorios de aplicaciones compatibles con AltStore. Construido desde cero con SwiftUI, está diseñado para ser rápido, eficiente y, sobre todo, robusto.

## La Falla de los Repositorios Grandes

Los clientes de tiendas alternativas tradicionales a menudo enfrentan un problema crítico: al intentar cargar un repositorio (fuente) grande o que contiene una o más aplicaciones con formato incorrecto (un "JSON malformado"), el proceso de sincronización falla por completo. Esto resulta en que **ninguna aplicación** de esa fuente se muestre, dejando al usuario sin acceso al contenido.

**SwiftStore ataca este problema de raíz.** Gracias a un decodificador JSON personalizado, la aplicación es capaz de:

1.  **Procesar las aplicaciones de forma individual:** En lugar de tratar el archivo JSON del repositorio como un todo o nada.
2.  **Ignorar entradas corruptas:** Si una aplicación en el repositorio tiene un error en su definición, SwiftStore simplemente la ignora y continúa con la siguiente.
3.  **Cargar el resto del contenido:** El resultado es que siempre verás todas las aplicaciones que *sí* están correctamente definidas, sin importar cuántas entradas fallidas haya en la fuente.

Esto hace de SwiftStore la solución ideal para usuarios que dependen de repositorios comunitarios grandes y en constante cambio, donde los errores son comunes.

---

## Características Principales

### Funcionalidad Core

- **Manejo Robusto de Fuentes:** Sincroniza repositorios grandes y con errores sin fallar.
- **Gestión de Múltiples Fuentes:** Añade, elimina y activa/desactiva fuentes fácilmente.
- **Cola de Descargas:** Descarga varias aplicaciones en segundo plano, una tras otra.
- **Gestor de Archivos:** Visualiza y gestiona los archivos `.ipa` descargados directamente en la app.
- **Deshacer Eliminación:** ¿Eliminaste una fuente por error? Simplemente agita tu dispositivo para deshacer la acción.
- **Estatus en Vivo:** Un discreto overlay te mantiene informado del estado de la sincronización de repositorios.

### Interfaz de Usuario

- **Interfaz Moderna con SwiftUI:** Una experiencia de usuario fluida y nativa.
- **Fondo Animado:** Un sutil fondo de "burbujas" que le da un toque dinámico a la interfaz (configurable).
- **Modo AMOLED:** Un verdadero modo negro para ahorrar batería en pantallas OLED.
- **Diseño "Liquid Glass":** Componentes con un elegante efecto de vidrio translúcido.

### Para Desarrolladores

- **Compilación sin Xcode:** El proyecto se compila usando un simple script (`build.sh`) que invoca a `swiftc` directamente. Ideal para entornos de CI/CD o para compilar desde la terminal.
- **Integración Continua:** Incluye un workflow de **GitHub Actions** (`build.yml`) que compila, versiona y crea un *release* automáticamente en cada push a la rama principal.
- **Exportador de Íconos Secreto:** Una herramienta oculta para generar todos los tamaños de íconos necesarios para una app de iOS a partir de un diseño hecho en SwiftUI. (Pista: toca 5 veces en la sección "Apariencia" en Ajustes).

---

## ¿Cómo Compilar?

Gracias a su sistema de compilación simplificado, no necesitas Xcode para generar el `.ipa`.

### Requisitos

- macOS con las herramientas de línea de comandos de Xcode instaladas.

### Pasos

1.  Clona el repositorio:
    ```bash
    git clone https://github.com/elmendezz/SwiftStore.git
    cd SwiftStore
    ```

2.  Ejecuta el script de compilación:
    ```bash
    ./build.sh
    ```

3.  ¡Listo! El script se encargará de compilar el código, empaquetar los assets y generar el archivo `SwiftStore.ipa` en la raíz del proyecto.

---

## Licencia

Copyright (c) 2026 elmendezz. Todos los derechos reservados.
