# LANAI - Dinamómetro Digital

![Flutter](https://img.shields.io/badge/Flutter-3.9.2-blue)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20Linux%20%7C%20macOS-green)
![License](https://img.shields.io/badge/license-Private-red)

Sistema completo de medición de fuerza mediante un dinamómetro digital inalámbrico. Combina hardware Arduino con una aplicación Flutter multiplataforma para registrar, analizar y visualizar datos de fuerza en tiempo real.

## 📋 Tabla de Contenidos

- [Descripción](#-descripción)
- [Características](#-características)
- [Requisitos de Hardware](#-requisitos-de-hardware)
- [Requisitos de Software](#-requisitos-de-software)
- [Arquitectura del Sistema](#-arquitectura-del-sistema)
- [Instalación](#-instalación)
  - [Configuración del Hardware](#configuración-del-hardware)
  - [Configuración de la Aplicación Flutter](#configuración-de-la-aplicación-flutter)
- [Uso](#-uso)
- [Modos de Operación](#-modos-de-operación)
- [Base de Datos](#-base-de-datos)
- [Tecnologías Utilizadas](#-tecnologías-utilizadas)
- [Estructura del Proyecto](#-estructura-del-proyecto)
- [Solución de Problemas](#-solución-de-problemas)

## 📝 Descripción

LANAI Dinamómetro Digital es un sistema integral para la medición y análisis de fuerza muscular. El proyecto consta de dos componentes principales:

1. **Hardware**: Un dinamómetro basado en Arduino que utiliza una celda de carga con amplificador HX711 y comunicación Bluetooth Low Energy (BLE).
2. **Software**: Una aplicación Flutter multiplataforma que recibe datos del dinamómetro, los visualiza en tiempo real y almacena mediciones para análisis posterior.

## ✨ Características

### 📱 Aplicación Flutter

- **Gestión de Perfiles**: Crea y administra múltiples perfiles de usuario para seguimiento individual
- **Conexión BLE**: Escaneo y conexión automática a dispositivos Bluetooth Low Energy
- **Múltiples Modos de Medición**:
  - **Fuerza Máxima**: Registro de fuerza máxima por mano (derecha/izquierda)
  - **Tiempo Real**: Visualización continua de datos de fuerza con gráficas
  - **Fuerza Explosiva**: Análisis del desarrollo de fuerza rápida con intervalos configurables
  - **Fuerza Crítica**: Determinación del umbral de fuerza crítica mediante pruebas incrementales
- **Historial Completo**: Consulta de sesiones anteriores con filtros por perfil y fecha
- **Gráficas Interactivas**: Visualización de datos mediante fl_chart
- **Base de Datos Local**: Almacenamiento persistente con SQLite
- **Interfaz Adaptativa**: Soporte para tema claro y oscuro
- **Multiplataforma**: Compatible con Android, iOS, Windows, Linux y macOS

### 🔧 Hardware Arduino

- **Lectura Precisa**: Utiliza el amplificador HX711 para lecturas exactas de la celda de carga
- **Comunicación BLE**: Transmisión de datos mediante Adafruit Bluefruit LE UART
- **Calibración**: Sistema de calibración con peso conocido
- **Función de Tara**: Puesta a cero del dinamómetro
- **Envío Periódico**: Transmisión de datos cada segundo
- **Comandos Remotos**: Recepción de comandos de tara (T) y calibración (C) desde la aplicación

## 🛠️ Requisitos de Hardware

### Componentes Necesarios

1. **Arduino** (Uno, Nano, o compatible)
2. **Celda de Carga** (Load Cell) - capacidad según aplicación (ej. 0-50 kg)
3. **Amplificador HX711** - módulo de conversión A/D para celda de carga
4. **Módulo Bluetooth LE** - Adafruit Bluefruit LE UART Friend
5. **Cables de Conexión**
6. **Fuente de Alimentación** - para Arduino (USB o batería)

### Diagrama de Conexiones

```
Arduino -> HX711:
  Pin 3 -> DT (Data)
  Pin 4 -> SCK (Clock)
  5V -> VCC
  GND -> GND

Arduino -> Bluefruit LE UART:
  Pin 8 -> TXO (RX en Arduino)
  Pin 9 -> RXI (TX en Arduino)
  Pin 11 -> CTS (opcional)
  Pin 12 -> MODE (no usado en UART Friend)
  5V -> VIN
  GND -> GND

HX711 -> Celda de Carga:
  E+ -> Cable Rojo (Excitación +)
  E- -> Cable Negro (Excitación -)
  A+ -> Cable Blanco (Señal +)
  A- -> Cable Verde (Señal -)
```

## 💻 Requisitos de Software

### Para el Hardware

- **Arduino IDE** 1.8.x o superior
- **Librerías Arduino**:
  - `HX711_ADC` - para el amplificador de celda de carga
  - `Adafruit_BluefruitLE_nRF51` - para comunicación BLE
  - `SoftwareSerial` - comunicación serie por software

### Para la Aplicación

- **Flutter SDK** 3.9.2 o superior
- **Dart SDK** (incluido con Flutter)
- **Android Studio** / **Xcode** / **Visual Studio** (según la plataforma objetivo)
- **Dispositivo con Bluetooth LE** (BLE 4.0 o superior)

## 🏗️ Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────────┐
│                  Aplicación Flutter                      │
│  ┌─────────────────────────────────────────────────┐   │
│  │         Interfaz de Usuario (Material)           │   │
│  └────────────────┬────────────────────────────────┘   │
│                   │                                      │
│  ┌────────────────▼────────────────────────────────┐   │
│  │          Gestión de Estado                       │   │
│  │    (Perfiles, Sesiones, Modos de Medición)      │   │
│  └────────┬───────────────────────────┬────────────┘   │
│           │                            │                 │
│  ┌────────▼──────────┐    ┌──────────▼─────────────┐  │
│  │ Flutter Blue Plus  │    │  SQLite Database       │  │
│  │  (Comunicación BLE)│    │  (Almacenamiento)      │  │
│  └────────┬──────────┘    └────────────────────────┘  │
└───────────┼─────────────────────────────────────────────┘
            │
    ┌───────▼────────┐
    │  Bluetooth LE   │
    └───────┬────────┘
            │
┌───────────▼─────────────────────────────────────────────┐
│                  Hardware Arduino                        │
│  ┌─────────────────────────────────────────────────┐   │
│  │       Adafruit Bluefruit LE UART Friend          │   │
│  └────────────────┬────────────────────────────────┘   │
│                   │                                      │
│  ┌────────────────▼────────────────────────────────┐   │
│  │         Microcontrolador Arduino                 │   │
│  │      (Procesamiento y Control)                   │   │
│  └────────┬───────────────────────────┬────────────┘   │
│           │                            │                 │
│  ┌────────▼──────────┐    ┌──────────▼─────────────┐  │
│  │   Amplificador     │    │    Comandos de         │  │
│  │     HX711          │    │  Tara/Calibración      │  │
│  └────────┬──────────┘    └────────────────────────┘  │
│           │                                             │
│  ┌────────▼──────────┐                                 │
│  │  Celda de Carga    │                                 │
│  │   (Load Cell)      │                                 │
│  └───────────────────┘                                 │
└─────────────────────────────────────────────────────────┘
```

## 📦 Instalación

### Configuración del Hardware

1. **Ensamblar el Hardware**:
   - Conecta la celda de carga al amplificador HX711 según el diagrama
   - Conecta el HX711 al Arduino (pines 3 y 4)
   - Conecta el módulo Bluefruit LE UART al Arduino (pines 8, 9, 11, 12)

2. **Cargar el Firmware**:
   ```bash
   # Instala las librerías necesarias desde el Library Manager de Arduino IDE
   # - HX711_ADC
   # - Adafruit BluefruitLE nRF51
   
   # Abre el archivo celdaCarga.ino en Arduino IDE
   # Selecciona tu placa Arduino y puerto serie
   # Haz clic en "Upload" para cargar el sketch
   ```

3. **Calibrar el Dinamómetro**:
   - Abre el Serial Monitor (115200 baud)
   - Envía el comando 'C' para iniciar la calibración
   - Sigue las instrucciones en el monitor serie
   - Coloca un peso conocido cuando se solicite
   - El factor de calibración se calculará y guardará automáticamente

### Configuración de la Aplicación Flutter

1. **Clonar el Repositorio**:
   ```bash
   git clone https://github.com/SergioLugo91/LANAI-Dinamometro-Digital-.git
   cd LANAI-Dinamometro-Digital-
   ```

2. **Instalar Dependencias**:
   ```bash
   flutter pub get
   ```

3. **Verificar la Configuración**:
   ```bash
   flutter doctor
   ```

4. **Ejecutar la Aplicación**:
   ```bash
   # Para Android
   flutter run -d android
   
   # Para iOS
   flutter run -d ios
   
   # Para Windows
   flutter run -d windows
   
   # Para Linux
   flutter run -d linux
   
   # Para macOS
   flutter run -d macos
   ```

## 🚀 Uso

### Primer Uso

1. **Encender el Hardware**:
   - Conecta el Arduino a una fuente de alimentación
   - El LED del módulo BLE debe parpadear indicando que está listo para conectarse

2. **Abrir la Aplicación**:
   - Inicia la aplicación en tu dispositivo
   - Concede los permisos de Bluetooth y ubicación cuando se soliciten

3. **Crear un Perfil**:
   - En la pantalla de inicio, introduce tu nombre
   - Haz clic en "Guardar nombre" para crear una nueva sesión
   - O selecciona un perfil existente si ya has usado la aplicación

4. **Conectar el Dispositivo BLE**:
   - Haz clic en "Conectar dispositivo BLE"
   - La aplicación escaneará dispositivos cercanos
   - Selecciona tu módulo Bluefruit de la lista
   - Espera a que la conexión se establezca (icono verde de Bluetooth)

5. **Seleccionar un Modo**:
   - Elige uno de los cuatro modos disponibles
   - Sigue las instrucciones específicas de cada modo

### Operación Normal

- **Realizar Tara**: Haz clic en el botón "Tara" para poner a cero el dinamómetro
- **Guardar Mediciones**: Los datos se guardan automáticamente en cada modo
- **Ver Historial**: Accede al icono de historial para revisar sesiones anteriores
- **Cerrar Sesión**: Haz clic en "Cerrar sesión" cuando termines de medir

## 📊 Modos de Operación

### 1. Fuerza Máxima (F. Máxima)

**Propósito**: Medir y registrar la fuerza máxima aplicada por cada mano.

**Características**:
- Medición independiente para mano derecha e izquierda
- Gráficas en tiempo real con valor actual y máximo
- Botón de cambio rápido entre manos
- Función de reset individual por mano
- Guardado simultáneo de ambos máximos

**Uso**:
1. Selecciona la mano activa (derecha o izquierda)
2. Aplica fuerza al dinamómetro
3. El sistema registra automáticamente el valor máximo
4. Cambia de mano con el botón "Actualizar"
5. Guarda los máximos cuando termines

### 2. Tiempo Real

**Propósito**: Visualizar datos de fuerza de forma continua con gráfica dinámica.

**Características**:
- Gráfica de línea en tiempo real (últimos 100 puntos)
- Indicador de fuerza actual y máxima
- Actualización automática cada segundo
- Ideal para ejercicios de resistencia

**Uso**:
1. El modo inicia automáticamente al entrar
2. Aplica fuerza y observa la gráfica en tiempo real
3. El sistema registra el valor máximo alcanzado
4. La gráfica se actualiza continuamente

### 3. Fuerza Explosiva (F. Explosiva)

**Propósito**: Analizar el desarrollo de fuerza en intervalos de tiempo cortos.

**Características**:
- Intervalos de trabajo y descanso configurables
- Contador regresivo visual
- Registro de fuerza máxima por intervalo
- Cálculo de RFD (Rate of Force Development)
- Gráfica comparativa de intervalos

**Uso**:
1. Configura los intervalos de trabajo y descanso
2. Inicia la prueba con el botón "Iniciar"
3. Aplica fuerza máxima durante cada intervalo de trabajo
4. Descansa durante los intervalos de descanso
5. El sistema guarda automáticamente los resultados

### 4. Fuerza Crítica (F. Crítica)

**Propósito**: Determinar el umbral de fuerza crítica mediante pruebas incrementales.

**Características**:
- Pruebas con diferentes porcentajes de la fuerza máxima
- Tiempo hasta el fallo en cada intensidad
- Cálculo de la fuerza crítica mediante regresión lineal
- Visualización del modelo de fuerza crítica
- Exportación de resultados

**Uso**:
1. Realiza una prueba de fuerza máxima previa
2. El sistema calcula automáticamente los porcentajes
3. Realiza cada prueba hasta el fallo
4. El sistema calcula la fuerza crítica
5. Revisa los resultados y gráficas

## 🗄️ Base de Datos

El sistema utiliza SQLite para almacenar de forma persistente:

### Tablas Principales

- **profiles**: Perfiles de usuario
  - `id`: Identificador único
  - `name`: Nombre del perfil

- **sessions**: Sesiones de medición
  - `id`: Identificador único
  - `profile_name`: Nombre del perfil asociado
  - `start_time`: Fecha/hora de inicio
  - `end_time`: Fecha/hora de finalización
  - `active`: Estado de la sesión (1=activa, 0=cerrada)

- **maxima**: Registros de fuerza máxima
  - `id`: Identificador único
  - `session_id`: Sesión asociada
  - `hand`: Mano (right/left)
  - `max_value`: Valor máximo registrado
  - `timestamp`: Marca de tiempo

- **explosive_force**: Datos de fuerza explosiva
  - `id`: Identificador único
  - `session_id`: Sesión asociada
  - `interval_num`: Número de intervalo
  - `max_value`: Fuerza máxima del intervalo
  - `rfd`: Tasa de desarrollo de fuerza
  - `timestamp`: Marca de tiempo

- **critical_force**: Datos de fuerza crítica
  - `id`: Identificador único
  - `session_id`: Sesión asociada
  - `percentage`: Porcentaje de la fuerza máxima
  - `time_to_failure`: Tiempo hasta el fallo
  - `timestamp`: Marca de tiempo

## 🔧 Tecnologías Utilizadas

### Frontend (Flutter)

- **Flutter**: Framework multiplataforma
- **Material Design**: Sistema de diseño de interfaz
- **flutter_blue_plus**: Comunicación Bluetooth Low Energy
- **fl_chart**: Gráficas y visualizaciones
- **sqflite**: Base de datos SQLite local
- **path_provider**: Acceso a rutas del sistema
- **shared_preferences**: Almacenamiento de preferencias
- **permission_handler**: Gestión de permisos del sistema

### Backend (Arduino)

- **Arduino Framework**: Plataforma de desarrollo
- **HX711_ADC**: Librería para amplificador de celda de carga
- **Adafruit_BluefruitLE_UART**: Comunicación BLE UART
- **SoftwareSerial**: Puerto serie por software

## 📁 Estructura del Proyecto

```
LANAI-Dinamometro-Digital-/
├── android/                 # Configuración Android
├── ios/                     # Configuración iOS
├── linux/                   # Configuración Linux
├── macos/                   # Configuración macOS
├── windows/                 # Configuración Windows
├── web/                     # Configuración Web
├── lib/
│   ├── main.dart           # Punto de entrada de la aplicación
│   └── src/
│       ├── database.dart           # Gestión de base de datos SQLite
│       ├── force_max_mode.dart     # Modo Fuerza Máxima
│       ├── history_page.dart       # Página de historial
│       ├── modes/
│       │   ├── realtime_mode.dart      # Modo Tiempo Real
│       │   ├── explosive_force_mode.dart # Modo Fuerza Explosiva
│       │   └── critical_force_mode.dart  # Modo Fuerza Crítica
│       └── widgets/
│           └── mode_card.dart      # Widget tarjeta de modo
├── test/                   # Tests unitarios
├── celdaCarga.ino         # Firmware Arduino
├── pubspec.yaml           # Dependencias Flutter
├── analysis_options.yaml  # Configuración de análisis estático
└── README.md              # Este archivo
```

## 🐛 Solución de Problemas

### El Arduino no se conecta por BLE

- Verifica que el módulo Bluefruit esté correctamente conectado
- Asegúrate de que el Arduino esté alimentado correctamente
- Revisa el monitor serie (115200 baud) para mensajes de error
- Comprueba que las librerías estén instaladas correctamente

### La aplicación no encuentra el dispositivo BLE

- Activa el Bluetooth en tu dispositivo
- Concede permisos de Bluetooth y ubicación a la aplicación
- Asegúrate de estar cerca del Arduino (< 10 metros)
- Reinicia el módulo Bluefruit desconectando y reconectando el Arduino
- En Android 12+, verifica los permisos BLUETOOTH_SCAN y BLUETOOTH_CONNECT

### Lecturas incorrectas o inestables

- Realiza una calibración del dinamómetro
- Ejecuta la función de tara antes de cada medición
- Verifica las conexiones de la celda de carga al HX711
- Asegúrate de que la celda de carga esté correctamente instalada
- Revisa el factor de calibración en el código Arduino

### La aplicación no guarda los datos

- Verifica los permisos de almacenamiento
- Comprueba que hay espacio disponible en el dispositivo
- Revisa los logs de la aplicación para errores de base de datos
- Asegúrate de que la sesión esté activa

### Problemas de rendimiento en gráficas

- Reduce el número de puntos mostrados en tiempo real
- Cierra aplicaciones en segundo plano
- Prueba en un dispositivo con mejores especificaciones

## 📄 Licencia

Este proyecto es privado y no está publicado bajo ninguna licencia de código abierto.

## 👥 Contribuciones

Este es un proyecto privado. Las contribuciones están limitadas a los colaboradores autorizados.

## 📧 Contacto

Para preguntas o soporte, contacta al propietario del repositorio: [SergioLugo91](https://github.com/SergioLugo91)

---

**Desarrollado con ❤️ usando Flutter y Arduino**
