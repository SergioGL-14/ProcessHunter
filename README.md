# ProcessHunter
### Cazador de Procesos Zombi

Herramienta de diagnóstico de procesos para Windows, escrita íntegramente en PowerShell con interfaz gráfica WPF construida en código puro — sin XAML. Detecta, clasifica y permite actuar sobre procesos zombi, sospechosos, degradantes y frikis con una estética cyberpunk inspirada en terminales de ciencia ficción.

---

## Requisitos

- Windows 10 / 11 (o Windows Server 2016+)
- PowerShell 5.1 o superior
- .NET Framework 4.5+ (incluido en Windows 10 por defecto)
- Recomendado: ejecutar como Administrador para acceder a todos los procesos del sistema

---

## Ejecución

```powershell
powershell -STA -ExecutionPolicy Bypass -File ProcessHunter.ps1
```

El script detecta automáticamente si no se está ejecutando en modo STA (requerido por WPF) y se relanza solo. No es necesario hacer nada manualmente.

---

## Clasificación de procesos

El motor de análisis evalúa cada proceso en tiempo real y lo encuadra en una de estas siete categorías:

| Categoría | Criterios de detección |
|-----------|------------------------|
| 🧟 **Zombi** | CPU < 0.5s acumulado, RAM < 8 MB, sin ventana visible, proceso padre muerto o inaccesible |
| ⚠️ **Sospechoso** | Ejecutable en rutas temporales (`%Temp%`, `AppData\Roaming`), sin firma digital en ubicación inusual |
| 🔋 **Degradante** | RAM > 500 MB o CPU acumulado > 60s |
| 🤖 **Friki** | Nombre contiene palabras clave de hacking/cracking, o ejecutable en Escritorio/Descargas con bajo consumo |
| 🔒 **Crítico** | Lista blanca interna de ~30 procesos de sistema Windows esenciales |
| ✅ **Inofensivo** | Marcado manualmente por el usuario como seguro |
| ⚙️ **Normal** | No encaja en ninguna categoría anterior |

Las marcas manuales (inofensivo, sospechoso, crítico) tienen prioridad sobre la clasificación automática y persisten durante la sesión activa.

---

## Interfaz

La ventana se divide en tres zonas principales:

**Barra superior** — cabecera con nombre de usuario y equipo, último escaneo y hora en vivo.

**Barra de herramientas** — acceso rápido a las operaciones principales: escanear, purgar zombis, exportar informe, activar auto-refresco y abrir el log completo. Incluye caja de búsqueda con filtrado en tiempo real por nombre, PID, usuario o ruta.

**Barra de filtros** — ocho botones para filtrar la lista por categoría. El botón activo se resalta; los demás se atenúan. Los badges de la derecha muestran el recuento actual de cada tipo de proceso problemático.

**Panel izquierdo (DataGrid)** — lista de todos los procesos con columnas para tipo, nombre, RAM, CPU, PID, usuario y hora de inicio. Las filas se colorean automáticamente según la categoría del proceso. Ordenados por peligrosidad: zombis y sospechosos primero.

**Panel derecho (detalles)** — al seleccionar un proceso se muestra toda la información extendida: ruta del ejecutable, firma digital verificada en tiempo real (`Get-AuthenticodeSignature`), usuario propietario, proceso padre con estado (vivo o muerto), RAM, CPU, hilos, handles, título de ventana. Incluye todos los botones de acción y clasificación manual.

**Bitácora** — panel inferior con registro de todas las acciones realizadas en la sesión, con timestamp y usuario.

---

## Acciones disponibles

Todas las acciones operan sobre el proceso seleccionado en el DataGrid:

- **Finalizar proceso** — llama a `Stop-Process -Force`. Pide confirmación siempre; doble advertencia si el proceso es crítico de sistema.
- **Abrir carpeta** — abre el Explorador de Windows en el directorio del ejecutable.
- **Buscar en Google** — abre el navegador con una búsqueda sobre el proceso para identificarlo.
- **Ver árbol de procesos** — muestra una ventana con el proceso padre, el proceso actual y todos sus hijos detectados, con RAM y clasificación de cada uno.
- **Copiar info al portapapeles** — genera un bloque de texto con todos los datos del proceso, listo para pegar en un ticket o informe.
- **Purgar todos los zombis** — muestra la lista completa de zombis detectados, pide confirmación y los elimina en lote. Reporta cuántos se pudieron finalizar y cuántos fallaron.
- **Auto-refresco** — re-escanea automáticamente cada 30 segundos. Se activa y desactiva con el botón de la toolbar.

---

## Clasificación manual

Cualquier proceso puede reclasificarse manualmente desde el panel de detalles. Las marcas se aplican inmediatamente y persisten durante la sesión:

- **Marcar como inofensivo** — fuerza categoría `SAFE` para ese PID, independientemente de lo que diga el análisis automático.
- **Marcar como sospechoso** — fuerza categoría `SUSPICIOUS`.
- **Marcar como crítico** — añade el nombre del proceso a la lista blanca de sistema. Afecta a todos los procesos con ese nombre, no solo al PID actual.
- **Quitar marca** — elimina cualquier clasificación manual y deja que el motor vuelva a evaluar el proceso en el próximo escaneo.

---

## Exportación de informes

El botón **Exportar informe** abre un diálogo para guardar en cuatro formatos:

| Formato | Contenido |
|---------|-----------|
| `.html` | Informe visual con estilos cyberpunk, badges de resumen y tabla completa. Abre en cualquier navegador. |
| `.txt`  | Listado plano con todos los datos de cada proceso, legible y fácil de incluir en tickets. |
| `.csv`  | Compatible con Excel, PowerBI o cualquier herramienta de análisis tabular. |
| `.json` | Estructura completa con metadatos del equipo y array de procesos. Útil para integración con otros sistemas. |

---

## Bitácora de auditoría

Cada acción que se realiza queda registrada automáticamente en:

```
%USERPROFILE%\Documents\ProcessHunter_Log.txt
```

Cada entrada incluye fecha/hora, nombre de usuario, acción realizada, nombre del proceso y PID. El panel inferior de la aplicación muestra las entradas más recientes en tiempo real. El botón **Ver Log Completo** abre el archivo directamente en el Bloc de notas.

---

## Detalles técnicos

El script no usa XAML ni ningún archivo externo. Toda la interfaz se construye en código PowerShell puro mediante el API de WPF:

- `System.Windows.Window`, `Grid`, `StackPanel`, `Border` — estructura de layout
- `System.Windows.Controls.DataGrid` — lista de procesos con `RowStyle` y `DataTrigger` para colorear filas por categoría
- `System.Windows.Threading.DispatcherTimer` — reloj en vivo y auto-refresco
- `Get-Process` + `Get-CimInstance Win32_Process` — obtención de datos y propietario de proceso
- `Get-AuthenticodeSignature` — verificación de firma digital del ejecutable
- `Invoke-CimMethod GetOwner` — resolución del usuario propietario
- Los `add_Click` de WPF usan `.Tag` del botón para pasar datos al handler, evitando el problema conocido de captura de closures en PowerShell

---

## Estructura del proyecto

```
ProcessHunter.ps1       Script principal. Autocontenido, sin dependencias externas.
ProcessHunter_Log.txt   Generado en ejecución en %USERPROFILE%\Documents\
```

---

## Capturas de pantalla

<img width="2378" height="1632" alt="image" src="https://github.com/user-attachments/assets/869238a7-8dbb-452a-9ba6-84bc53f97486" />

---

## Licencia

Uso interno. Sin licencia de distribución pública por el momento.
