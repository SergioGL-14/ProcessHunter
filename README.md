# ProcessHunter
### Zombie Process Hunter

Process diagnostics tool for Windows, written entirely in PowerShell with a WPF GUI built in pure code — no XAML. It detects, classifies and lets you act on zombie, suspicious, resource-hungry and sketchy processes with a cyberpunk aesthetic inspired by science-fiction terminals.

---

## Requirements

- Windows 10 / 11 (or Windows Server 2016+)
- PowerShell 5.1 or higher
- .NET Framework 4.5+ (included in Windows 10 by default)
- Recommended: run as Administrator to access every system process

---

## Running

```powershell
powershell -STA -ExecutionPolicy Bypass -File ProcessHunter.ps1
```

The script detects on its own when it is not running in STA mode (required by WPF) and relaunches itself. No manual steps needed.

---

## Process classification

The analysis engine evaluates every process in real time and places it in one of these seven categories (labels shown are the ones the interface displays):

| Category | Detection criteria |
|-----------|------------------------|
| 🧟 **Zombi** | CPU < 0.5s accumulated, RAM < 8 MB, no visible window, dead or unreachable parent process |
| ⚠️ **Sospechoso** | Executable in temporary paths (`%Temp%`, `AppData\Roaming`), or unsigned binary in an unusual location |
| 🔋 **Degradante** | RAM > 500 MB or accumulated CPU > 60s |
| 🤖 **Friki** | Name contains hacking/cracking keywords, or executable on Desktop/Downloads with low usage |
| 🔒 **Crítico** | Internal whitelist of ~30 essential Windows system processes |
| ✅ **Inofensivo** | Manually marked as safe by the user |
| ⚙️ **Normal** | Fits none of the categories above |

Manual marks (safe, suspicious, critical) take priority over automatic classification and persist for the active session.

---

## Interface

The window is divided into three main zones:

**Top bar** — header with username and machine name, last scan time and a live clock.

**Toolbar** — quick access to the main operations: scan, purge zombies, export report, toggle auto-refresh and open the full log. Includes a search box with real-time filtering by name, PID, user or path.

**Filter bar** — eight buttons to filter the list by category. The active button is highlighted; the rest dim. Badges on the right show the current count of each problematic process type.

**Left panel (DataGrid)** — list of all processes with columns for type, name, RAM, CPU, PID, user and start time. Rows are colored automatically according to the process category. Sorted by danger level: zombies and suspicious processes first.

**Right panel (details)** — selecting a process shows all extended information: executable path, digital signature verified in real time (`Get-AuthenticodeSignature`), owning user, parent process with status (alive or dead), RAM, CPU, threads, handles, window title. All action buttons and manual classification live here.

**Audit log** — bottom panel recording every action taken during the session, with timestamp and user.

---

## Available actions

All actions operate on the process selected in the DataGrid:

- **Finalizar proceso** (Kill process) — calls `Stop-Process -Force`. Always asks for confirmation; double warning if the process is a critical system one.
- **Abrir carpeta** (Open folder) — opens Windows Explorer at the executable's directory.
- **Buscar en Google** (Search on Google) — opens the browser with a search about the process to identify it.
- **Ver árbol de procesos** (View process tree) — shows a window with the parent process, the current one and all detected children, with RAM and classification for each.
- **Copiar info al portapapeles** (Copy info to clipboard) — generates a text block with all process data, ready to paste into a ticket or report.
- **Purgar todos los zombis** (Purge all zombies) — shows the full list of detected zombies, asks for confirmation and kills them in batch. Reports how many were terminated and how many failed.
- **Auto-refresco** (Auto-refresh) — re-scans automatically every 30 seconds. Toggled from the toolbar button.

Kill and purge actions are destructive: they terminate processes with `Stop-Process -Force` and cannot be undone. The application always asks for confirmation before running them.

---

## Manual classification

Any process can be reclassified manually from the details panel. Marks apply immediately and persist for the session:

- **Marcar como inofensivo** (Mark as safe) — forces category `SAFE` for that PID, regardless of what the automatic analysis says.
- **Marcar como sospechoso** (Mark as suspicious) — forces category `SUSPICIOUS`.
- **Marcar como crítico** (Mark as critical) — adds the process name to the system whitelist. Affects every process with that name, not just the current PID.
- **Quitar marca** (Remove mark) — clears any manual classification and lets the engine re-evaluate the process on the next scan.

---

## Report export

The **Exportar informe** (Export report) button opens a save dialog with four formats:

| Format | Content |
|---------|-----------|
| `.html` | Visual report with cyberpunk styling, summary badges and the full table. Opens in any browser. Process text is HTML-escaped before insertion. |
| `.txt`  | Plain listing with every process field, readable and easy to paste into tickets. |
| `.csv`  | Compatible with Excel, PowerBI or any tabular analysis tool. |
| `.json` | Full structure with machine metadata and a process array. Useful for integration with other systems. |

---

## Audit log

Every action performed is logged automatically to:

```
%USERPROFILE%\Documents\ProcessHunter_Log.txt
```

Each entry includes date/time, username, action performed, process name and PID. The bottom panel of the application shows the most recent entries in real time. The **Ver Log Completo** (View Full Log) button opens the file directly in Notepad.

---

## Technical details

The script uses no XAML and no external files. The whole interface is built in pure PowerShell through the WPF API:

- `System.Windows.Window`, `Grid`, `StackPanel`, `Border` — layout structure
- `System.Windows.Controls.DataGrid` — process list with `RowStyle` and `DataTrigger` to color rows by category
- `System.Windows.Threading.DispatcherTimer` — live clock and auto-refresh
- `Get-Process` + `Get-CimInstance Win32_Process` — data gathering and process ownership
- `Get-AuthenticodeSignature` — digital signature verification of the executable
- `Invoke-CimMethod GetOwner` — resolving the owning user
- WPF `add_Click` handlers use the button's `.Tag` to pass data, avoiding PowerShell's known closure-capture problem

---

## Tests

`tests/Test-ProcessHunterExport.ps1` verifies the HTML report generator: it checks that reserved characters are encoded, that null input yields an empty string, and that an injection attempt through process names, owners, paths and host metadata lands escaped in the output. Run it with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-ProcessHunterExport.ps1
```

It only needs the export module, so it runs without loading the WPF interface.

---

## Project structure

```
ProcessHunter.ps1              Main script. Self-contained, no external dependencies.
ProcessHunter.Export.ps1       HTML report generator (dot-sourced by the main script).
tests/Test-ProcessHunterExport.ps1  Tests for the report generator.
ProcessHunter_Log.txt          Generated at runtime in %USERPROFILE%\Documents\.
```

---

## Screenshot

<img width="2378" height="1632" alt="image" src="https://github.com/user-attachments/assets/869238a7-8dbb-452a-9ba6-84bc53f97486" />

---

## License

Distributed under the MIT license — see [LICENSE](LICENSE).
