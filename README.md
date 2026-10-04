# Robot Cortacésped Autónomo

Robot cortacésped autónomo desarrollado mediante una arquitectura distribuida que integra ESP32, Raspberry Pi, ROS2, una aplicación Flutter y módulos de visión artificial.

El sistema combina control de bajo nivel, procesamiento de alto nivel, navegación, percepción del entorno y supervisión remota.

## Arquitectura del sistema

El proyecto está dividido en cuatro módulos principales:

### Firmware ESP32

El ESP32 se encarga del control de bajo nivel del robot.

Entre sus funciones principales se encuentran:

- Control de motores de tracción
- Control del motor brushless
- Sistema de corte
- Sensores ultrasónicos
- IMU
- Monitoreo de batería
- Buzzer
- Display
- Gestión de seguridad
- Comunicación serial con Raspberry Pi

El firmware fue desarrollado utilizando C++ y PlatformIO con una arquitectura modular.

### Raspberry Pi / ROS2

La Raspberry Pi actúa como computadora principal del robot y ejecuta los nodos ROS2 encargados de la coordinación del sistema.

Entre sus funciones se incluyen:

- Control de actuadores
- Comunicación con el ESP32
- Procesamiento de sensores
- Navegación autónoma
- Navegación perimetral
- Navegación mediante líneas paralelas
- Seguimiento GPS
- Cerco virtual
- Integración de visión artificial
- Inicio coordinado de los nodos mediante ROS2

### Aplicación Flutter

La aplicación permite supervisar y controlar el robot de forma remota.

Incluye funciones como:

- Control manual
- Selección de modos de operación
- Visualización de sensores
- Estado general del robot
- Visualización de posición GPS
- Configuración
- Cerco virtual
- Visualización de cámara

La comunicación entre la aplicación y el sistema se realiza mediante WebSocket.

### Visión Artificial

El sistema de visión procesa las imágenes obtenidas por la cámara del robot.

Se desarrollaron modelos para:

- Detección de obstáculos
- Identificación de áreas con pasto y sin pasto

Los modelos fueron entrenados y posteriormente exportados para su ejecución en la Raspberry Pi.

## Tecnologías utilizadas

- ESP32
- Raspberry Pi
- ROS2
- C++
- Python
- PlatformIO
- Flutter
- Dart
- OpenCV
- YOLO
- TensorFlow Lite
- GPS
- WebSocket
- Visión artificial
- Sistemas embebidos

## Flujo general del sistema

`Aplicación → Raspberry Pi / ROS2 → ESP32 → Actuadores y sistema de corte`

Sistema de percepción:

`Cámara → Visión Artificial → Raspberry Pi → Navegación y toma de decisiones`

## Estructura del repositorio

~~~text
autonomous-lawn-mower-robot/
├── app/
├── docs/
│   └── Project_Report.ipynb
├── firmware/
│   ├── include/
│   ├── src/
│   └── platformio.ini
├── raspberry-pi/
│   ├── pkg_actuadores/
│   ├── pkg_bringup/
│   ├── pkg_esp32_bridge/
│   ├── pkg_navegacion/
│   ├── pkg_sensores/
│   └── pkg_vision/
├── vision/
│   ├── models/
│   └── training-models/
├── LICENSE
└── README.md
~~~

## Firmware

El código correspondiente al ESP32 se encuentra en:

`firmware/`

Incluye módulos independientes para el control de motores, sensores, seguridad, batería, sistema de corte y comunicación con la Raspberry Pi.

## Raspberry Pi

Los paquetes y nodos ROS2 se encuentran en:

`raspberry-pi/`

El software está organizado por funcionalidades de navegación, sensores, actuadores, visión y comunicación con el ESP32.

## Aplicación

El código de la aplicación Flutter se encuentra en:

`app/`

## Visión Artificial

Los nodos y modelos utilizados para la percepción del entorno se encuentran en:

`vision/`

## Documentación

La documentación técnica del proyecto se encuentra en:

`docs/Project_Report.ipynb`

## Autor

Victor Gabriel Curiel Gonzalez 
Judith Giselle Jacquet Boschi  
Fabrizzio Sebastian Bianchini Morel  
Ximena Lujan Quenhan Riveros  

Universidad Nacional de Asunción  
Facultad de Ingeniería  
Ingeniería Mecatrónica

## Licencia

Este proyecto está distribuido bajo la licencia MIT.
