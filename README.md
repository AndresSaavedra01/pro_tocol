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

## Planificación: Sprint 1

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

## Backlog del Sprint 1: Conectividad y Estructura Base

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

---

---

## Planificación: Sprint 2

El objetivo de este segundo bloque es integrar el asistente de inteligencia artificial de forma completa, conectándolo a la terminal SSH activa y dotando al sistema de capacidades de diagnóstico, ejecución supervisada y persistencia de conversaciones.

### Estructura de la Épica IA

1. **Configuración y Cliente:** Integración con la API de Ollama y persistencia de credenciales.
2. **Interfaz de Chat:** Componente visual de conversación con soporte de streaming token a token.
3. **Bridge IA-Terminal:** Ejecución de bloques de código generados por la IA directamente en la terminal activa.
4. **Contexto y Seguridad:** Inyección de metadatos del servidor y sanitización de scripts antes de su ejecución.
5. **Historial y UX:** Persistencia de consultas entre sesiones y experiencia de carga fluida.

---

## Backlog del Sprint 2: Asistente IA con Ollama

| ID | Historia de Usuario | Descripción / Criterios de Aceptación | SP |
| :--- | :--- | :--- | :--- |
| **ES-52** | **Refactorización de Arquitectura y Código Limpio** | Reestructuración del proyecto bajo principios SOLID, separación estricta de capas y eliminación de dependencias circulares. | 5 |
| **ES-42** | **Cliente API (Ollama)** | Implementación del cliente HTTP para comunicarse con la API de Ollama. Soporte de streaming de respuesta y manejo de errores de red. | 5 |
| **ES-43** | **Configuración de IA** | Pantalla de configuración para ingresar y persistir la URL base y credenciales de Ollama. Validación del endpoint antes de guardar. | 3 |
| **ES-45** | **Interfaz de Chat** | Componente visual de conversación con burbujas diferenciadas (usuario / IA), auto-scroll y renderizado de bloques de código Markdown. | 3 |
| **ES-47** | **Inyección de Contexto del Servidor** | Recolección automática de metadatos del servidor activo (distro, hardware, servicios) para incluirlos como contexto en cada prompt enviado a la IA. | 4 |
| **ES-48** | **Seguridad y Sanitización** | Revisión y filtrado de los scripts generados por la IA antes de permitir su ejecución. Confirmación explícita del usuario para comandos destructivos. | 3 |
| **ES-50** | **Historial de Consultas** | Persistencia del historial de chat en base de datos local (Hive/Isar). El contexto de la conversación se restaura al reiniciar la sesión. | 4 |
| **ES-51** | **UX de Carga (Streaming)** | Visualización token a token de la respuesta de la IA mediante `StreamProvider`. Indicador de escritura animado mientras la respuesta llega. | 3 |
| **ES-46** | **Bridge IA-Terminal** | Botón "Ejecutar en Terminal" en cada bloque de código del chat. Inyección del comando en la terminal xterm activa usando el singleton compartido. | 3 |
| **ES-49** | **Explicador de Errores** | Captura automática de errores en la terminal SSH. Botón para enviar el error al asistente y recibir un diagnóstico con solución propuesta. | 5 |
| **TOTAL** | | **Épica ES-44 completada al 100%** | **38** |

---

## Criterios de Aceptación Generales — Sprint 2 (DoD)

1. **Conexión con Ollama:** La app debe conectarse a la API configurada y recibir respuestas en streaming sin errores de red.
2. **Bridge funcional:** Un bloque de código generado por la IA debe poder ejecutarse en la terminal activa con un solo toque.
3. **Contexto real:** Cada prompt enviado a la IA debe incluir los metadatos actuales del servidor conectado.
4. **Seguridad:** Ningún comando marcado como destructivo puede ejecutarse sin confirmación explícita del usuario.
5. **Persistencia:** El historial de conversación debe sobrevivir al cierre y reinicio de la aplicación.
6. **Diagnóstico:** Al producirse un error en la terminal, el usuario puede enviarlo al asistente y recibir una propuesta de solución.

## Notas de Implementación — Sprint 2

* El **singleton `Terminal`** es compartido entre `TerminalTab` y `ChatIaTab` vía inyección de dependencias (`get_it`), garantizando que ambas pestañas operen sobre la misma instancia xterm.
* La **captura de errores** se realiza en la capa SSH (no en xterm), utilizando un sentinel `__PROTO_EXIT__:$?` para detectar exit codes en shell interactivo sin interferir con el output normal.
* El **streaming** se implementa con `StreamProvider` de Riverpod, permitiendo reconstrucciones de UI token a token sin afectar el rendimiento de la terminal SSH paralela.
* Las **sesiones temporales** también tienen acceso al asistente de IA bajo la misma arquitectura de contexto que los servidores guardados.
