# Pro-Tocol: SSH Visual Client

Aplicación móvil desarrollada en Flutter que permite la administración remota de servidores Linux a través de una interfaz gráfica intuitiva, eliminando la dependencia obligatoria de la terminal para tareas comunes.

## Definición del Proyecto

El sistema permite la conexión a servidores mediante el protocolo SSH, organizando el acceso a través de perfiles de usuario. La aplicación se distingue por ofrecer un entorno visual para la gestión de archivos, monitoreo de recursos y despliegue de servicios mediante plantillas preconfiguradas.

### Características Principales

* **Sistema de Perfiles:** Acceso multiusuario con configuraciones personalizadas para cada perfil al estilo de plataformas de streaming.
* **Gestor de Servidores:** Configuración visual de aplicaciones y servicios sin necesidad de comandos manuales.
* **Despliegue por Plantillas:** Instalación automatizada de stacks (Web, Base de Datos) mediante checklists de validación y configuraciones básicas automáticas.
* **Explorador de Archivos:** Gestión funcional para subir, descargar, editar y codificar archivos de texto con editor integrado.
* **Monitoreo en Tiempo Real:** Visualización del estado del hardware (CPU, RAM, Disco), procesos y puertos activos.
* **Asistente de IA:** Chat integrado conectado a una API propia (Ollama) para la generación y ejecución supervisada de scripts en el servidor.

---

## Especificaciones Técnicas

* **Framework:** Flutter
* **Comunicación SSH:** Librería dartssh2
* **Backend IA:** API propia basada en Ollama
* **Arquitectura:** División en tres capas (Presentación, Dominio y Datos)
* **Patrón de Diseño:** MVC (Modelo-Vista-Controlador)

---

## Planificación: Sprint 0

El objetivo de este primer bloque es establecer la base de conectividad, la persistencia de perfiles y la navegación visual básica.

### Estructura de Interfaz

1.  **Pantalla de Perfiles:** Creación y selección de perfiles con nombre y avatar.
2.  **Sidebar (Menú Lateral):** Ubicación de servidores guardados, sesiones temporales y botones de creación/eliminación.
3.  **Formularios:** Captura de credenciales (Usuario, IP, Contraseña o Key).
4.  **Vistas de Servidor:**
    * Pestaña de Estado: Monitoreo de hardware (CPU, RAM, Disco).
    * Pestaña de Terminal: Consola interactiva funcional.
    * Pestaña de Explorador: Visualización de archivos y directorios (Solo vista).

---

## Backlog del Sprint 0: Conectividad y Estructura Base

| ID | Rol | Historia de Usuario | Descripción / Criterios de Aceptación | SP |
| :--- | :--- | :--- | :--- | :--- |
| **US-A1** | **Dev A (View)** | **Gestor de Perfiles** | Pantalla inicial estilo Netflix para crear/seleccionar perfil (Nombre y Avatar). | 3 |
| **US-A2** | **Dev A (View)** | **Layout y Sidebar** | Menú lateral con secciones para Servidores y Sesiones Temporales. Botones de añadir/eliminar. | 5 |
| **US-A3** | **Dev A (View)** | **Formularios de Conexión** | Interfaz para capturar IP, Usuario, Password o Key. Validación visual de campos. | 3 |
| **US-A4** | **Dev A (View)** | **Pestañas de Servidor** | Implementación de TabController: Estado (Monitoreo), Terminal y Explorador. | 5 |
| **US-B1** | **Dev B (Model)** | **Entidades de Dominio** | Definición de clases Profile, Server, TempSession, ServerStats y FileItem. | 2 |
| **US-B2** | **Dev B (Model)** | **Persistencia Local** | Configuración de DB (Hive/Isar) para perfiles y servidores guardados. | 5 |
| **US-B3** | **Dev B (Model)** | **Motor SSH y SFTP** | Implementación de `dartssh2`. Métodos para ejecutar comandos y listar archivos. | 8 |
| **US-C1** | **Dev C (Controller)** | **Navegación y Perfiles** | Lógica para cambiar de perfil y gestionar qué componente se muestra en el Sidebar. | 5 |
| **US-C2** | **Dev C (Controller)** | **Orquestador SSH** | Manejo de sesiones activas en paralelo y gestión de errores de conexión. | 5 |
| **US-C3** | **Dev C (Controller)** | **Lógica de Pestañas** | Timers para métricas de CPU/RAM, gestión de streams de terminal y navegación SFTP. | 8 |
| **TOTAL** | | | **Carga balanceada: Dev A (16), Dev B (15), Dev C (18)** | **49** |

---

## Criterios de Aceptación Generales (DoD)
1. **Conexión Exitosa:** Se debe lograr el acceso a un servidor Linux real desde la app.
2. **Persistencia:** Al reiniciar la app, los perfiles y servidores creados deben seguir ahí.
3. **Multitarea:** Se debe poder abrir una terminal en una sesión temporal y otra en un servidor guardado simultáneamente.
4. **Monitoreo:** La pestaña de estado debe mostrar datos reales de CPU, RAM y Disco del servidor.
5. **Navegación:** El explorador debe listar archivos de cualquier ruta solicitada (ej. `/etc` o `/var`).
## Notas de Implementación

* Las **Sesiones Temporales** no se persisten en la base de datos local; se eliminan al cerrar la aplicación o la sesión.
* El **Explorador de Archivos** en el Sprint 1 se limita a la visualización de la estructura de directorios para asegurar estabilidad.
* La arquitectura debe garantizar que las tres pestañas del servidor mantengan su estado independiente durante la conexión activa.

---


## Planificación: Sprint 1
El objetivo de este primer bloque es transformar el prototipo base de Pro-Tocol en una aplicación estable mediante la aplicación de estándares SOLID, garantizando un manejo de errores resiliente e implementando las capacidades núcleo de gestión visual (SFTP y Monitoreo de Hardware).

### Alcance

| Épica | Enfoque |
|---|---|
| **Refactorización del Código** | Modularización, SOLID/DRY, Validaciones, Manejo de errores, Gestión de perfiles, Pulido de UX. |
| **Expansión de Nuevas Funcionalidades** | Dashboard de Monitoreo, Explorador SFTP, Historial de Comandos, Detección de Distro, Instalador Gráfico, Sistema de Templates. |

### Fuera de Alcance (Sprint 1)

- Entrenamiento de la IA
- Conexión de IA
- Asistente de IA integrado (Ollama) — planificado para Sprint 2

### Backlog del Sprint 1

| ID | Rol | Historia de Usuario | Descripción / Criterios de Aceptación | SP |
|---|---|---|---|---|
| ES-34 | Dev A | Modularización | Reorganizar el proyecto en módulos claros (core, features, shared). Sin dependencias circulares. Modelos independientes de la UI. | 5 |
| ES-35 | Dev A | Optimización DRY y SOLID | Eliminar código duplicado. Centralizar lógica SSH en un único Service. Clases con una sola responsabilidad (SRP). | 5 |
| ES-36 | Dev A | Gestión Avanzada de Perfiles | Editar/eliminar perfiles con datos precargados. Diálogo de confirmación. Actualización inmediata en DB local. | 3 |
| ES-37 | Dev B | Validación de Formularios | Validar formato IP/Dominio. Bloquear envío si faltan campos. Mensajes de error en rojo bajo el campo. | 2 |
| ES-38 | Dev B | Gestión de Errores de Red | Capturar excepciones dartssh2 (Timeout, Auth Failed). Vista de error con botón "Reintentar". Log técnico para depuración. | 3 |
| ES-39 | Dev B | Pulido de Interfaz (UX) | Animaciones de transición (Fade/Slide). Eliminar iconos sin funcionalidad. Corregir bug visual del cursor en terminal. | 2 |
| ES-16 | Dev B | Dashboard de Monitoreo | CPU, RAM y Disco en tiempo real. Listado de procesos con opción kill. Estado de servicios Systemd. | 5 |
| ES-18 | Dev C | Detección de Distro | Ejecutar `cat /etc/os-release` al conectar. Identificar apt/pacman/dnf. Mostrar logo de distro en el header. | 3 |
| ES-40 | Dev C | Historial de Comandos | Guardar últimos 50 comandos en sesión. Navegar con flechas. Opción de limpiar historial. | 3 |
| ES-41 | Dev C | Instalador Gráfico | Botones de instalar para apps comunes. Ejecución en segundo plano. Notificación de éxito o fallo. | 5 |
| ES-12 | Dev A | Explorador SFTP Funcional | Subida de archivos por selector o drag & drop. Mover archivos entre directorios. Visualización de progreso. | 8 |
| ES-20 | Dev C | Sistema de Templates | Checklist de validación antes de aplicar plantilla. Automatización de configuración básica. Reporte de cambios aplicados. | 5 |
| **TOTAL** | | | Carga balanceada: Dev A (18), Dev B (12), Dev C (16) | **49** |

### Criterios de Aceptación Generales (DoD)

1. **Conexión Exitosa:** Se debe lograr el acceso a un servidor Linux real desde la app.
2. **Persistencia:** Al reiniciar la app, los perfiles y servidores creados deben seguir ahí.
3. **Multitarea:** Se debe poder abrir una terminal en una sesión temporal y otra en un servidor guardado simultáneamente.
4. **Monitoreo:** La pestaña de monitoreo debe mostrar datos reales de CPU, RAM y Disco del servidor.
5. **Navegación:** El explorador debe listar archivos de cualquier ruta solicitada (ej. `/etc` o `/var`).


