#Requires -Version 5.1
<#
.SYNOPSIS
    ProcessHunter v2.0 - Cazador de Procesos Zombi
.DESCRIPTION
    Herramienta de diagnóstico con GUI WPF (sin XAML) estilo cyberpunk/retro.
    Detecta, clasifica y permite actuar sobre procesos zombi, sospechosos y degradantes.
.NOTES
    PowerShell 5.1+ | WPF puro en código | Sin XAML
    Ejecutar: powershell -STA -ExecutionPolicy Bypass -File ProcessHunter.ps1
#>

# ══════════════════════════════════════════════════════════════
# STA THREAD CHECK (WPF require STA)
# ══════════════════════════════════════════════════════════════
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    Start-Process powershell -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

# ══════════════════════════════════════════════════════════════
# ENSAMBLADOS
# ══════════════════════════════════════════════════════════════
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ══════════════════════════════════════════════════════════════
# GLOBALES DE SCRIPT
# ══════════════════════════════════════════════════════════════
$Script:Version      = "2.0.0"
$Script:LogPath      = "$env:USERPROFILE\Documents\ProcessHunter_Log.txt"
$Script:SafePIDs     = [System.Collections.Generic.HashSet[int]]::new()
$Script:SuspPIDs     = [System.Collections.Generic.HashSet[int]]::new()
$Script:CritNames    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$Script:FilterCat    = "ALL"
$Script:AllProcs     = [System.Collections.Generic.List[PSObject]]::new()
$Script:AutoRefreshOn = $false
$Script:UI           = @{}
$Script:CurrentProc  = $null

# ══════════════════════════════════════════════════════════════
# PALETA DE COLORES
# ══════════════════════════════════════════════════════════════
$Script:CLR = @{
    BgMain    = [System.Windows.Media.Color]::FromRgb(5,  9,  5)
    BgHeader  = [System.Windows.Media.Color]::FromRgb(3, 14,  3)
    BgPanel   = [System.Windows.Media.Color]::FromRgb(9, 17,  9)
    BgCell    = [System.Windows.Media.Color]::FromRgb(11, 21, 11)
    BgAlt     = [System.Windows.Media.Color]::FromRgb(13, 24, 13)
    BgLog     = [System.Windows.Media.Color]::FromRgb(3,  10,  3)

    Green     = [System.Windows.Media.Color]::FromRgb(0, 255,  70)
    GreenMid  = [System.Windows.Media.Color]::FromRgb(0, 180,  50)
    GreenDark = [System.Windows.Media.Color]::FromRgb(0,  55,  18)
    GreenDim  = [System.Windows.Media.Color]::FromRgb(50, 120, 60)

    Cyan      = [System.Windows.Media.Color]::FromRgb(0, 230, 230)
    CyanDark  = [System.Windows.Media.Color]::FromRgb(0,  45,  55)

    Yellow    = [System.Windows.Media.Color]::FromRgb(255, 205,  0)
    YellowDk  = [System.Windows.Media.Color]::FromRgb( 40,  32,  0)

    Red       = [System.Windows.Media.Color]::FromRgb(255,  60,  60)
    RedDark   = [System.Windows.Media.Color]::FromRgb( 45,   8,   8)

    Orange    = [System.Windows.Media.Color]::FromRgb(255, 145,   0)
    OrangeDk  = [System.Windows.Media.Color]::FromRgb( 40,  20,   0)

    Purple    = [System.Windows.Media.Color]::FromRgb(185,  50, 255)
    PurpleDk  = [System.Windows.Media.Color]::FromRgb( 28,   0,  45)

    GrayGrn   = [System.Windows.Media.Color]::FromRgb(85, 125, 85)
    GrayDark  = [System.Windows.Media.Color]::FromRgb(12,  22, 12)
    White     = [System.Windows.Media.Color]::FromRgb(205, 255, 205)
    Border    = [System.Windows.Media.Color]::FromRgb(0,   80,  0)
    BorderDim = [System.Windows.Media.Color]::FromRgb(0,   40,  0)
}

function New-Brush {
    param([System.Windows.Media.Color]$c)
    $b = [System.Windows.Media.SolidColorBrush]::new($c)
    $b.Freeze()
    return $b
}

# Pre-compilar pinceles
$Script:BR = @{}
foreach ($k in $Script:CLR.Keys) { $Script:BR[$k] = New-Brush $Script:CLR[$k] }
$Script:BR.Transparent = [System.Windows.Media.Brushes]::Transparent

# ══════════════════════════════════════════════════════════════
# CATEGORÍAS DE PROCESO
# ══════════════════════════════════════════════════════════════
$Script:CAT = [ordered]@{
    ZOMBIE     = @{ Icon="🧟";  Label="Zombi";      Fg=$Script:CLR.Green;    Bg=[System.Windows.Media.Color]::FromRgb( 8, 28,  8) }
    SUSPICIOUS = @{ Icon="⚠️";  Label="Sospechoso"; Fg=$Script:CLR.Yellow;   Bg=[System.Windows.Media.Color]::FromRgb(32, 26,  0) }
    DEGRADING  = @{ Icon="🔋";  Label="Degradante"; Fg=$Script:CLR.Orange;   Bg=[System.Windows.Media.Color]::FromRgb(32, 16,  0) }
    FRIKI      = @{ Icon="🤖";  Label="Friki";      Fg=$Script:CLR.Purple;   Bg=[System.Windows.Media.Color]::FromRgb(20,  0, 32) }
    CRITICAL   = @{ Icon="🔒";  Label="Crítico";    Fg=$Script:CLR.Cyan;     Bg=[System.Windows.Media.Color]::FromRgb( 0, 18, 32) }
    SAFE       = @{ Icon="✅";  Label="Inofensivo"; Fg=$Script:CLR.GreenMid; Bg=[System.Windows.Media.Color]::FromRgb( 0, 28, 10) }
    NORMAL     = @{ Icon="⚙️";  Label="Normal";     Fg=$Script:CLR.GrayGrn;  Bg=[System.Windows.Media.Color]::FromRgb(10, 19, 10) }
}

# ══════════════════════════════════════════════════════════════
# LISTA BLANCA DE PROCESOS DE SISTEMA
# ══════════════════════════════════════════════════════════════
@(
    'System','Idle','svchost','lsass','winlogon','csrss','wininit',
    'services','smss','explorer','spoolsv','dwm','taskhost','taskhostw',
    'RuntimeBroker','ShellExperienceHost','SearchIndexer','SearchUI',
    'ctfmon','audiodg','fontdrvhost','sihost','WUDFHost','NisSrv',
    'MsMpEng','SecurityHealthService','WmiPrvSE','dllhost','conhost',
    'Registry','MemCompression','vmmem','wsappx','TextInputHost',
    'StartMenuExperienceHost','LsaIso','SgrmBroker','SecurityHealthSystray',
    'sppsvc','SysMain','wlms','TrustedInstaller','TiWorker','WerFault',
    'ApplicationFrameHost','UserOOBEBroker','PresentationFontCache'
) | ForEach-Object { $Script:CritNames.Add($_) | Out-Null }

# ══════════════════════════════════════════════════════════════
# MOTOR DE ANÁLISIS DE PROCESOS
# ══════════════════════════════════════════════════════════════
function Get-ProcessSignature {
    param([string]$path)
    if (-not $path -or $path -eq 'N/A' -or $path -eq '') { return '❌ Sin ruta' }
    if (-not (Test-Path $path -ErrorAction SilentlyContinue)) { return '❌ Archivo no encontrado' }
    try {
        $sig = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
        switch ($sig.Status) {
            'Valid'     { return "✅ $($sig.SignerCertificate.Subject -replace '^CN=([^,]+).*$','$1')" }
            'NotSigned' { return '🚫 Sin firma digital' }
            'HashMismatch' { return '🔴 Firma alterada' }
            default     { return "⚠️ $($sig.Status)" }
        }
    } catch { return '❓ No verificable' }
}

function Get-ParentProcessName {
    param([int]$ppid)
    if ($ppid -le 0) { return 'N/A' }
    try {
        $p = Get-Process -Id $ppid -ErrorAction Stop
        return "$($p.Name)  (PID: $ppid)"
    } catch {
        return "⚰️ Proceso muerto  (PID: $ppid)"
    }
}

function Get-ProcessCategory {
    param($proc, [hashtable]$cimMap)

    $pid_  = $proc.Id
    $name_ = $proc.Name

    # Marcas manuales tienen prioridad
    if ($Script:SafePIDs.Contains($pid_))     { return 'SAFE' }
    if ($Script:SuspPIDs.Contains($pid_))     { return 'SUSPICIOUS' }
    if ($Script:CritNames.Contains($name_))   { return 'CRITICAL' }

    $ram  = try { $proc.WorkingSet64 / 1MB } catch { 0 }
    $cpu  = try { $proc.CPU }                 catch { 0 }
    $path = try { $proc.MainModule.FileName } catch { '' }

    # Degradante: alto consumo de recursos
    if ($ram -gt 500 -or $cpu -gt 60) { return 'DEGRADING' }

    # Sospechoso: rutas temporales o sin firma en ruta inusual
    if ($path -match '(?i)(\\[Tt]emp\\|\\[Tt]mp\\|AppData\\Local\\Temp|\\[Rr]ecycle|AppData\\Roaming\\[^\\]+\.exe)') {
        return 'SUSPICIOUS'
    }

    # Friki: nombres de hacking, juegos, ejecutables en Escritorio/Descargas
    if ($name_ -match '(?i)(hack|crack|keygen|patch|injector|cheat|trainer|bypass|warez|torrent)') {
        return 'FRIKI'
    }
    if ($path -match '(?i)(\\Desktop\\|\\Escritorio\\|\\[Dd]ownloads\\|\\[Dd]escargas\\)' -and $ram -lt 20) {
        return 'FRIKI'
    }

    # Zombi: sin CPU, poca RAM, sin ventana, padre muerto o proceso huérfano
    if ($cpu -lt 0.5 -and $ram -lt 8 -and $proc.MainWindowHandle -eq [IntPtr]::Zero) {
        $ppid = if ($cimMap -and $cimMap[$pid_]) { $cimMap[$pid_].ParentProcessId } else { 0 }
        if ($ppid -gt 4) {
            $parentAlive = try { $null -ne (Get-Process -Id $ppid -ErrorAction Stop) } catch { $false }
            if (-not $parentAlive) { return 'ZOMBIE' }
        }
        if ($ram -lt 2 -and -not $path) { return 'ZOMBIE' }
    }

    return 'NORMAL'
}

function Invoke-ProcessScan {
    $result = [System.Collections.Generic.List[PSObject]]::new()

    # Datos CIM (para propietario y padre)
    $cimMap = @{}
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
            $cimMap[$_.ProcessId] = $_
        }
    } catch {}

    foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        try {
            $pid_     = $proc.Id
            $name_    = $proc.Name
            $ram_     = try { [math]::Round($proc.WorkingSet64 / 1MB, 1) }   catch { 0.0 }
            $cpu_     = try { [math]::Round($proc.CPU, 2) }                   catch { 0.0 }
            $path_    = try { $proc.MainModule.FileName }                      catch { 'N/A' }
            $title_   = try { $proc.MainWindowTitle }                          catch { '' }
            $threads_ = try { $proc.Threads.Count }                            catch { 0 }
            $handles_ = try { $proc.HandleCount }                              catch { 0 }
            $start_   = try { $proc.StartTime.ToString('yyyy-MM-dd HH:mm') }  catch { 'N/A' }
            $ppid_    = if ($cimMap[$pid_]) { $cimMap[$pid_].ParentProcessId } else { 0 }

            $owner_ = 'N/A'
            if ($cimMap[$pid_]) {
                try {
                    $ownerResult = $cimMap[$pid_] | Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue
                    if ($ownerResult -and $ownerResult.User) {
                        $owner_ = if ($ownerResult.Domain) { "$($ownerResult.Domain)\$($ownerResult.User)" } else { $ownerResult.User }
                    }
                } catch {}
            }

            $cat_   = Get-ProcessCategory -proc $proc -cimMap $cimMap
            $style_ = $Script:CAT[$cat_]

            $result.Add([PSCustomObject]@{
                PID         = $pid_
                Name        = $name_
                Category    = $cat_
                Icon        = $style_.Icon
                Label       = $style_.Label
                RAM         = $ram_
                CPU         = $cpu_
                Path        = if ($path_) { $path_ } else { 'N/A' }
                Owner       = $owner_
                StartTime   = $start_
                ParentPID   = $ppid_
                Threads     = $threads_
                Handles     = $handles_
                WindowTitle = $title_
            }) | Out-Null
        } catch { <# Proceso inaccesible, ignorar #> }
    }

    # Ordenar: peligrosos primero
    $order = @{ ZOMBIE=0; SUSPICIOUS=1; DEGRADING=2; FRIKI=3; NORMAL=4; SAFE=5; CRITICAL=6 }
    return $result | Sort-Object { $order[$_.Category] }, Name
}

# ══════════════════════════════════════════════════════════════
# SISTEMA DE LOGGING
# ══════════════════════════════════════════════════════════════
function Write-AuditLog {
    param([string]$action, [string]$procName = '', [int]$procPid = 0)
    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$env:USERNAME] $action"
    if ($procName) { $entry += " | $procName" }
    if ($procPid -gt 0) { $entry += " (PID:$procPid)" }

    try {
        $dir = Split-Path $Script:LogPath -Parent
        if (-not (Test-Path $dir -ErrorAction SilentlyContinue)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $Script:LogPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}

    try {
        if ($Script:UI.LogBox) {
            $Script:UI.LogBox.Dispatcher.Invoke([Action]{
                $newText = $entry + "`n" + $Script:UI.LogBox.Text
                $Script:UI.LogBox.Text = if ($newText.Length -gt 8000) { $newText.Substring(0,8000) } else { $newText }
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    } catch {}
}

# ══════════════════════════════════════════════════════════════
# FUNCIONES AYUDANTES DE WPF
# ══════════════════════════════════════════════════════════════
function New-T {   # Thickness
    param($u=0, $t=0, $r=0, $b=0)
    if ($t -eq 0 -and $r -eq 0 -and $b -eq 0) { [System.Windows.Thickness]::new($u) }
    else { [System.Windows.Thickness]::new($u,$t,$r,$b) }
}

function New-TextBlock {
    param(
        [string]$text    = '',
        [double]$size    = 11,
        $fg              = $null,
        [bool]$bold      = $false,
        [bool]$wrap      = $false
    )
    $tb = [System.Windows.Controls.TextBlock]::new()
    $tb.Text = $text
    $tb.FontSize = $size
    $tb.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $tb.Foreground = if ($fg) { $fg } else { $Script:BR.Green }
    $tb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    if ($bold) { $tb.FontWeight = [System.Windows.FontWeights]::Bold }
    if ($wrap) { $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap }
    return $tb
}

function New-Button {
    param(
        [string]$label,
        $bg         = $null,
        $fg         = $null,
        $border     = $null,
        [double]$h  = 30,
        [scriptblock]$onClick = {}
    )
    $bg     = if ($bg)     { $bg }     else { $Script:BR.GreenDark }
    $fg     = if ($fg)     { $fg }     else { $Script:BR.Green }
    $border = if ($border) { $border } else { $Script:BR.Border }

    $btn = [System.Windows.Controls.Button]::new()
    $btn.Content = $label
    $btn.Height = $h
    $btn.Background = $bg
    $btn.Foreground = $fg
    $btn.BorderBrush = $border
    $btn.BorderThickness = New-T 1
    $btn.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $btn.FontSize = 12
    $btn.Cursor = [System.Windows.Input.Cursors]::Hand
    $btn.Margin = New-T 0 2 0 2
    $btn.Padding = New-T 10 0 10 0
    $btn.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left

    $capturedBg = $bg
    $btn.add_MouseEnter({ param($s,$e) $s.Opacity = 0.80 })
    $btn.add_MouseLeave({ param($s,$e) $s.Opacity = 1.0 })
    $btn.add_Click($onClick)
    return $btn
}

function New-Separator {
    $sep = [System.Windows.Controls.Separator]::new()
    $sep.Background = $Script:BR.BorderDim
    $sep.Margin = New-T 0 5 0 5
    return $sep
}

function New-GridRowDef {
    param($height, [System.Windows.GridUnitType]$unit = [System.Windows.GridUnitType]::Pixel)
    $r = [System.Windows.Controls.RowDefinition]::new()
    $r.Height = [System.Windows.GridLength]::new($height, $unit)
    return $r
}

function New-GridColDef {
    param($width, [System.Windows.GridUnitType]$unit = [System.Windows.GridUnitType]::Pixel)
    $c = [System.Windows.Controls.ColumnDefinition]::new()
    $c.Width = [System.Windows.GridLength]::new($width, $unit)
    return $c
}

# ══════════════════════════════════════════════════════════════
# CONSTRUCCIÓN DE LA VENTANA PRINCIPAL
# ══════════════════════════════════════════════════════════════
function Build-MainWindow {

    # ── VENTANA ──────────────────────────────────────────────
    $win = [System.Windows.Window]::new()
    $win.Title  = "ProcessHunter v$($Script:Version)  –  El Cazador de Procesos Zombi"
    $win.Width  = 1600
    $win.Height = 1100
    $win.MinWidth  = 1200
    $win.MinHeight = 860
    $win.Background  = $Script:BR.BgMain
    $win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $win.FontFamily  = [System.Windows.Media.FontFamily]::new('Consolas')

    # ── GRID RAÍZ  (6 filas) ─────────────────────────────────
    $root = [System.Windows.Controls.Grid]::new()
    $root.RowDefinitions.Add((New-GridRowDef 72))    # 0  Header/título
    $root.RowDefinitions.Add((New-GridRowDef 52))    # 1  Barra de herramientas
    $root.RowDefinitions.Add((New-GridRowDef 44))    # 2  Filtros de categoría
    $root.RowDefinitions.Add((New-GridRowDef 1 ([System.Windows.GridUnitType]::Star))) # 3  Contenido
    $root.RowDefinitions.Add((New-GridRowDef 155))   # 4  Bitácora
    $root.RowDefinitions.Add((New-GridRowDef 32))    # 5  Barra de estado
    $win.Content = $root

    # ══════════════════════════════════════════════════════════
    # FILA 0 – CABECERA
    # ══════════════════════════════════════════════════════════
    $headerBorder = [System.Windows.Controls.Border]::new()
    $headerBorder.Background = New-Brush $Script:CLR.BgHeader
    $headerBorder.BorderBrush = $Script:BR.Border
    $headerBorder.BorderThickness = New-T 0 0 0 2
    [System.Windows.Controls.Grid]::SetRow($headerBorder, 0)
    $root.Children.Add($headerBorder) | Out-Null

    $hGrid = [System.Windows.Controls.Grid]::new()
    $hGrid.ColumnDefinitions.Add((New-GridColDef 1 ([System.Windows.GridUnitType]::Star)))
    $hGrid.ColumnDefinitions.Add((New-GridColDef 220))
    $headerBorder.Child = $hGrid

    # Izquierda: icono + título
    $hLeft = [System.Windows.Controls.StackPanel]::new()
    $hLeft.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $hLeft.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $hLeft.Margin = New-T 15 0 0 0
    [System.Windows.Controls.Grid]::SetColumn($hLeft, 0)
    $hGrid.Children.Add($hLeft) | Out-Null

    $hIcon = New-TextBlock '🧟' 32 $Script:BR.Green
    $hIcon.Margin = New-T 0 0 12 0
    $hLeft.Children.Add($hIcon) | Out-Null

    $hTitleStack = [System.Windows.Controls.StackPanel]::new()
    $hLeft.Children.Add($hTitleStack) | Out-Null
    $hTitleStack.Children.Add((New-TextBlock 'PROCESSHUNTER' 26 $Script:BR.Green $true)) | Out-Null
    $hTitleStack.Children.Add((New-TextBlock "El Cazador de Procesos Zombi  ·  v$($Script:Version)" 11 $Script:BR.GreenMid)) | Out-Null

    # Derecha: info usuario / último escaneo
    $hRight = [System.Windows.Controls.StackPanel]::new()
    $hRight.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $hRight.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $hRight.Margin = New-T 0 0 15 0
    [System.Windows.Controls.Grid]::SetColumn($hRight, 1)
    $hGrid.Children.Add($hRight) | Out-Null

    $Script:UI.UserLabel     = New-TextBlock "👤 $env:USERNAME  |  🖥️ $env:COMPUTERNAME" 9 $Script:BR.GrayGrn
    $Script:UI.LastScanLabel = New-TextBlock '🕐 Escaneo: no realizado' 9 $Script:BR.GrayGrn
    $hRight.Children.Add($Script:UI.UserLabel)     | Out-Null
    $hRight.Children.Add($Script:UI.LastScanLabel) | Out-Null

    # ══════════════════════════════════════════════════════════
    # FILA 1 – BARRA DE HERRAMIENTAS
    # ══════════════════════════════════════════════════════════
    $toolBorder = [System.Windows.Controls.Border]::new()
    $toolBorder.Background = New-Brush ([System.Windows.Media.Color]::FromRgb(7,14,7))
    $toolBorder.BorderBrush = $Script:BR.BorderDim
    $toolBorder.BorderThickness = New-T 0 0 0 1
    $toolBorder.Padding = New-T 10 5 10 5
    [System.Windows.Controls.Grid]::SetRow($toolBorder, 1)
    $root.Children.Add($toolBorder) | Out-Null

    $toolSP = [System.Windows.Controls.StackPanel]::new()
    $toolSP.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $toolBorder.Child = $toolSP

    # Botón ESCANEAR
    $Script:UI.BtnScan = New-Button '🔄  ESCANEAR PROCESOS' -h 34 -onClick { Do-Scan }
    $Script:UI.BtnScan.Width = 230
    $toolSP.Children.Add($Script:UI.BtnScan) | Out-Null

    $toolSP.Children.Add((Add-ToolSep)) | Out-Null

    # Botón PURGAR ZOMBIS
    $Script:UI.BtnPurge = New-Button '💀  PURGAR TODOS LOS ZOMBIS' `
        -bg (New-Brush $Script:CLR.RedDark) -fg (New-Brush $Script:CLR.Red) `
        -border (New-Brush $Script:CLR.Red) -h 34 -onClick { Do-PurgeZombies }
    $Script:UI.BtnPurge.Width = 255
    $toolSP.Children.Add($Script:UI.BtnPurge) | Out-Null

    $toolSP.Children.Add((Add-ToolSep)) | Out-Null

    # Botón EXPORTAR
    $Script:UI.BtnExport = New-Button '📤  EXPORTAR INFORME' `
        -bg (New-Brush $Script:CLR.CyanDark) -fg (New-Brush $Script:CLR.Cyan) `
        -border (New-Brush $Script:CLR.Cyan) -h 34 -onClick { Do-Export }
    $Script:UI.BtnExport.Width = 210
    $toolSP.Children.Add($Script:UI.BtnExport) | Out-Null

    $toolSP.Children.Add((Add-ToolSep)) | Out-Null

    # Botón AUTO-REFRESCO
    $Script:UI.BtnAuto = New-Button '⏱️  AUTO: OFF' -h 34 -onClick { Do-ToggleAuto }
    $Script:UI.BtnAuto.Width = 160
    $Script:UI.BtnAuto.Foreground = $Script:BR.GrayGrn
    $toolSP.Children.Add($Script:UI.BtnAuto) | Out-Null

    $toolSP.Children.Add((Add-ToolSep)) | Out-Null

    # Botón VER LOG
    $Script:UI.BtnOpenLog = New-Button '📋  VER LOG COMPLETO' `
        -bg (New-Brush $Script:CLR.GreenDark) -fg $Script:BR.GreenMid -h 34 `
        -onClick { Start-Process notepad.exe $Script:LogPath }
    $Script:UI.BtnOpenLog.Width = 200
    $toolSP.Children.Add($Script:UI.BtnOpenLog) | Out-Null

    # Caja de búsqueda (derecha)
    $searchOuter = [System.Windows.Controls.Border]::new()
    $searchOuter.Background = $Script:BR.BgPanel
    $searchOuter.BorderBrush = $Script:BR.Border
    $searchOuter.BorderThickness = New-T 1
    $searchOuter.CornerRadius = [System.Windows.CornerRadius]::new(3)
    $searchOuter.Margin = New-T 12 3 0 3
    $searchOuter.Padding = New-T 6 0 6 0
    $searchOuter.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $searchSP = [System.Windows.Controls.StackPanel]::new()
    $searchSP.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $searchOuter.Child = $searchSP

    $searchSP.Children.Add((New-TextBlock '🔍 ' 11 $Script:BR.GreenMid)) | Out-Null

    $Script:UI.SearchBox = [System.Windows.Controls.TextBox]::new()
    $Script:UI.SearchBox.Width = 250
    $Script:UI.SearchBox.Height = 22
    $Script:UI.SearchBox.Background = $Script:BR.Transparent
    $Script:UI.SearchBox.Foreground = $Script:BR.Green
    $Script:UI.SearchBox.CaretBrush = $Script:BR.Green
    $Script:UI.SearchBox.BorderThickness = New-T 0
    $Script:UI.SearchBox.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $Script:UI.SearchBox.FontSize = 13
    $Script:UI.SearchBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $Script:UI.SearchBox.add_TextChanged({ Do-ApplyFilter })
    $searchSP.Children.Add($Script:UI.SearchBox) | Out-Null

    $toolSP.Children.Add($searchOuter) | Out-Null

    # ══════════════════════════════════════════════════════════
    # FILA 2 – BARRA DE FILTROS
    # ══════════════════════════════════════════════════════════
    $filterBorder = [System.Windows.Controls.Border]::new()
    $filterBorder.Background = New-Brush ([System.Windows.Media.Color]::FromRgb(5,12,5))
    $filterBorder.BorderBrush = $Script:BR.BorderDim
    $filterBorder.BorderThickness = New-T 0 0 0 1
    $filterBorder.Padding = New-T 8 3 8 3
    [System.Windows.Controls.Grid]::SetRow($filterBorder, 2)
    $root.Children.Add($filterBorder) | Out-Null

    $filterSP = [System.Windows.Controls.StackPanel]::new()
    $filterSP.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $filterSP.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $filterBorder.Child = $filterSP

    $filterLabel = New-TextBlock 'FILTRAR: ' 11 $Script:BR.GrayGrn
    $filterLabel.Margin = New-T 0 0 6 0
    $filterSP.Children.Add($filterLabel) | Out-Null

    $filterDefs = @(
        @{ L='⚡ TODOS';       C='ALL';        Fg=$Script:CLR.Green;    Bg=$Script:CLR.GreenDark }
        @{ L='🧟 ZOMBI';      C='ZOMBIE';     Fg=$Script:CLR.Green;    Bg=[System.Windows.Media.Color]::FromRgb(5,22,5) }
        @{ L='⚠️ SOSPECHOSO'; C='SUSPICIOUS'; Fg=$Script:CLR.Yellow;   Bg=$Script:CLR.YellowDk }
        @{ L='🔋 DEGRADANTE'; C='DEGRADING';  Fg=$Script:CLR.Orange;   Bg=$Script:CLR.OrangeDk }
        @{ L='🤖 FRIKI';      C='FRIKI';      Fg=$Script:CLR.Purple;   Bg=$Script:CLR.PurpleDk }
        @{ L='🔒 CRÍTICO';    C='CRITICAL';   Fg=$Script:CLR.Cyan;     Bg=$Script:CLR.CyanDark }
        @{ L='✅ INOFENSIVO'; C='SAFE';       Fg=$Script:CLR.GreenMid; Bg=[System.Windows.Media.Color]::FromRgb(0,24,8) }
        @{ L='⚙️ NORMAL';     C='NORMAL';     Fg=$Script:CLR.GrayGrn;  Bg=$Script:CLR.GrayDark }
    )

    $Script:UI.FilterBtns = @{}
    foreach ($fd in $filterDefs) {
        $fb = [System.Windows.Controls.Button]::new()
        $fb.Content = $fd.L
        $fb.Height = 30
        $fb.Margin = New-T 2 0 2 0
        $fb.Padding = New-T 9 0 9 0
        $fb.Background = New-Brush $fd.Bg
        $fb.Foreground = New-Brush $fd.Fg
        $fb.BorderBrush = New-Brush $fd.Fg
        $fb.BorderThickness = New-T 1
        $fb.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
        $fb.FontSize = 12
        $fb.Cursor = [System.Windows.Input.Cursors]::Hand
        $fb.Tag = $fd.C
        $fb.add_Click({ param($s,$e)
            $Script:FilterCat = $s.Tag
            Do-ApplyFilter
        })
        $Script:UI.FilterBtns[$fd.C] = $fb
        $filterSP.Children.Add($fb) | Out-Null
    }

    # Contador de procesos por categoría (a la derecha)
    $Script:UI.FilterCountsSP = [System.Windows.Controls.StackPanel]::new()
    $Script:UI.FilterCountsSP.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $Script:UI.FilterCountsSP.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $Script:UI.FilterCountsSP.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $Script:UI.FilterCountsSP.Margin = New-T 0 0 12 0
    $filterBorder.Child = $null
    $filterFullGrid = [System.Windows.Controls.Grid]::new()
    $filterBorder.Child = $filterFullGrid
    $filterFullGrid.Children.Add($filterSP) | Out-Null
    $filterFullGrid.Children.Add($Script:UI.FilterCountsSP) | Out-Null

    # ══════════════════════════════════════════════════════════
    # FILA 3 – CONTENIDO PRINCIPAL (DataGrid | Panel detalles)
    # ══════════════════════════════════════════════════════════
    $mainGrid = [System.Windows.Controls.Grid]::new()
    $mainGrid.ColumnDefinitions.Add((New-GridColDef 1.65 ([System.Windows.GridUnitType]::Star)))
    $mainGrid.ColumnDefinitions.Add((New-GridColDef 1    ([System.Windows.GridUnitType]::Star)))
    [System.Windows.Controls.Grid]::SetRow($mainGrid, 3)
    $root.Children.Add($mainGrid) | Out-Null

    # ── COLUMNA IZQUIERDA: DataGrid ───────────────────────────
    $leftBorder = [System.Windows.Controls.Border]::new()
    $leftBorder.BorderBrush = $Script:BR.BorderDim
    $leftBorder.BorderThickness = New-T 0 0 1 0
    [System.Windows.Controls.Grid]::SetColumn($leftBorder, 0)
    $mainGrid.Children.Add($leftBorder) | Out-Null

    $Script:UI.DataGrid = [System.Windows.Controls.DataGrid]::new()
    $dg = $Script:UI.DataGrid
    $dg.AutoGenerateColumns = $false
    $dg.CanUserAddRows = $false
    $dg.CanUserDeleteRows = $false
    $dg.CanUserReorderColumns = $true
    $dg.CanUserResizeColumns = $true
    $dg.IsReadOnly = $true
    $dg.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::Single
    $dg.Background = $Script:BR.BgPanel
    $dg.Foreground = $Script:BR.Green
    $dg.BorderThickness = New-T 0
    $dg.RowBackground = $Script:BR.BgPanel
    $dg.AlternatingRowBackground = New-Brush $Script:CLR.BgAlt
    $dg.GridLinesVisibility = [System.Windows.Controls.DataGridGridLinesVisibility]::Horizontal
    $dg.HorizontalGridLinesBrush = $Script:BR.BorderDim
    $dg.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $dg.FontSize = 13
    $dg.ColumnHeaderHeight = 34
    $dg.RowHeight = 28
    $dg.Margin = New-T 0

    # Estilo de cabecera de columna
    $colHdrStyle  = [System.Windows.Style]::new([System.Windows.Controls.Primitives.DataGridColumnHeader])
    $hdrBgBrush   = New-Brush ([System.Windows.Media.Color]::FromRgb(3,13,3))
    $hdrFont      = [System.Windows.Media.FontFamily]::new('Consolas')
    $hdrBorderTh  = [System.Windows.Thickness]::new(0,0,1,2)
    $hdrPadding   = [System.Windows.Thickness]::new(7,0,7,0)
    $hdrFontSize  = [double]11.5

    $s1 = [System.Windows.Setter]::new(); $s1.Property = [System.Windows.Controls.Control]::BackgroundProperty;   $s1.Value = $hdrBgBrush
    $s2 = [System.Windows.Setter]::new(); $s2.Property = [System.Windows.Controls.Control]::ForegroundProperty;   $s2.Value = $Script:BR.GreenMid
    $s3 = [System.Windows.Setter]::new(); $s3.Property = [System.Windows.Controls.Control]::FontFamilyProperty;   $s3.Value = $hdrFont
    $s4 = [System.Windows.Setter]::new(); $s4.Property = [System.Windows.Controls.Control]::FontSizeProperty;     $s4.Value = $hdrFontSize
    $s5 = [System.Windows.Setter]::new(); $s5.Property = [System.Windows.Controls.Control]::BorderBrushProperty;  $s5.Value = $Script:BR.Border
    $s6 = [System.Windows.Setter]::new(); $s6.Property = [System.Windows.Controls.Control]::BorderThicknessProperty; $s6.Value = $hdrBorderTh
    $s7 = [System.Windows.Setter]::new(); $s7.Property = [System.Windows.Controls.Control]::PaddingProperty;      $s7.Value = $hdrPadding
    $colHdrStyle.Setters.Add($s1)
    $colHdrStyle.Setters.Add($s2)
    $colHdrStyle.Setters.Add($s3)
    $colHdrStyle.Setters.Add($s4)
    $colHdrStyle.Setters.Add($s5)
    $colHdrStyle.Setters.Add($s6)
    $colHdrStyle.Setters.Add($s7)
    $dg.ColumnHeaderStyle = $colHdrStyle

    # Estilo de fila con color por categoría (DataTriggers)
    $rowStyle = [System.Windows.Style]::new([System.Windows.Controls.DataGridRow])
    $rsCursor = [System.Windows.Setter]::new()
    $rsCursor.Property = [System.Windows.Controls.Control]::CursorProperty
    $rsCursor.Value = [System.Windows.Input.Cursors]::Hand
    $rowStyle.Setters.Add($rsCursor)

    foreach ($catKey in $Script:CAT.Keys) {
        $catStyle = $Script:CAT[$catKey]
        $dt = [System.Windows.DataTrigger]::new()
        $dt.Binding = [System.Windows.Data.Binding]::new('Category')
        $dt.Value = $catKey
        $bgBrush = New-Brush $catStyle.Bg
        $fgBrush = New-Brush $catStyle.Fg
        $bgSet = [System.Windows.Setter]::new()
        $bgSet.Property = [System.Windows.Controls.Control]::BackgroundProperty
        $bgSet.Value = $bgBrush
        $fgSet = [System.Windows.Setter]::new()
        $fgSet.Property = [System.Windows.Controls.Control]::ForegroundProperty
        $fgSet.Value = $fgBrush
        $dt.Setters.Add($bgSet)
        $dt.Setters.Add($fgSet)
        $rowStyle.Triggers.Add($dt)
    }
    $dg.RowStyle = $rowStyle

    # Estilo de celda
    $cellStyle = [System.Windows.Style]::new([System.Windows.Controls.DataGridCell])
    $cs1 = [System.Windows.Setter]::new()
    $cs1.Property = [System.Windows.Controls.Control]::BorderThicknessProperty
    $cs1.Value = [System.Windows.Thickness]::new(0)
    $cs2 = [System.Windows.Setter]::new()
    $cs2.Property = [System.Windows.Controls.Control]::FocusVisualStyleProperty
    $cs2.Value = $null
    $cs3 = [System.Windows.Setter]::new()
    $cs3.Property = [System.Windows.Controls.Control]::PaddingProperty
    $cs3.Value = [System.Windows.Thickness]::new(5,0,5,0)
    $cellStyle.Setters.Add($cs1)
    $cellStyle.Setters.Add($cs2)
    $cellStyle.Setters.Add($cs3)
    $dg.CellStyle = $cellStyle

    # Definición de columnas
    $colDefs = @(
        @{ H='TIPO';      B='Label';     W=90  }
        @{ H='PROCESO';   B='Name';      W=160 }
        @{ H='RAM (MB)';  B='RAM';       W=72  }
        @{ H='CPU (s)';   B='CPU';       W=62  }
        @{ H='PID';       B='PID';       W=52  }
        @{ H='USUARIO';   B='Owner';     W=120 }
        @{ H='INICIO';    B='StartTime'; W=128 }
    )
    foreach ($cd in $colDefs) {
        $col = [System.Windows.Controls.DataGridTextColumn]::new()
        $col.Header = $cd.H
        $col.Binding = [System.Windows.Data.Binding]::new($cd.B)
        $col.Width = [System.Windows.Controls.DataGridLength]::new($cd.W)
        $dg.Columns.Add($col)
    }

    $dg.add_SelectionChanged({ param($s,$e)
        $sel = $s.SelectedItem
        if ($sel) { Do-UpdateDetails $sel }
    })

    $leftBorder.Child = $dg

    # ── COLUMNA DERECHA: PANEL DE DETALLES ───────────────────
    $rightBorder = [System.Windows.Controls.Border]::new()
    $rightBorder.Background = $Script:BR.BgPanel
    [System.Windows.Controls.Grid]::SetColumn($rightBorder, 1)
    $mainGrid.Children.Add($rightBorder) | Out-Null

    $detailScroll = [System.Windows.Controls.ScrollViewer]::new()
    $detailScroll.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $detailScroll.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
    $rightBorder.Child = $detailScroll

    $detailSP = [System.Windows.Controls.StackPanel]::new()
    $detailSP.Margin = New-T 14 10 14 10
    $detailScroll.Content = $detailSP

    # Título del panel
    $detailTitle = New-TextBlock '[ DETALLES DEL PROCESO ]' 14 $Script:BR.Green $true
    $detailTitle.Margin = New-T 0 0 0 8
    $detailSP.Children.Add($detailTitle) | Out-Null

    # Badge de categoría
    $Script:UI.CatBadge = [System.Windows.Controls.Border]::new()
    $Script:UI.CatBadge.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $Script:UI.CatBadge.Padding = New-T 10 5 10 5
    $Script:UI.CatBadge.Margin = New-T 0 0 0 10
    $Script:UI.CatBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $Script:UI.CatBadge.Background = $Script:BR.GreenDark
    $Script:UI.CatBadgeText = New-TextBlock 'Selecciona un proceso de la lista' 12 $Script:BR.Green $true
    $Script:UI.CatBadge.Child = $Script:UI.CatBadgeText
    $detailSP.Children.Add($Script:UI.CatBadge) | Out-Null

    # Campos de detalle
    $Script:UI.DetailFields = @{}
    $fieldDefs = @(
        @{ Label='Nombre';        Key='Nombre' }
        @{ Label='PID';           Key='PID' }
        @{ Label='Clasificación'; Key='Clasificación' }
        @{ Label='Ruta';          Key='Ruta' }
        @{ Label='Firma digital'; Key='Firma' }
        @{ Label='Usuario';       Key='Usuario' }
        @{ Label='Proceso padre'; Key='Padre' }
        @{ Label='RAM';           Key='RAM' }
        @{ Label='CPU';           Key='CPU' }
        @{ Label='Inicio';        Key='Inicio' }
        @{ Label='Hilos';         Key='Hilos' }
        @{ Label='Handles';       Key='Handles' }
        @{ Label='Título ventana';Key='Título' }
    )
    foreach ($fd in $fieldDefs) {
        $row = [System.Windows.Controls.Grid]::new()
        $row.Margin = New-T 0 2 0 2
        $row.ColumnDefinitions.Add((New-GridColDef 108))
        $row.ColumnDefinitions.Add((New-GridColDef 1 ([System.Windows.GridUnitType]::Star)))

        $lbl = New-TextBlock "$($fd.Label):" 9.5 $Script:BR.GreenDim
        $lbl.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
        $lbl.Margin = New-T 0 1 6 0
        [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
        $row.Children.Add($lbl) | Out-Null

        $val = New-TextBlock '—' 10.5 $Script:BR.White
        $val.TextWrapping = [System.Windows.TextWrapping]::Wrap
        [System.Windows.Controls.Grid]::SetColumn($val, 1)
        $row.Children.Add($val) | Out-Null

        $Script:UI.DetailFields[$fd.Key] = $val
        $detailSP.Children.Add($row) | Out-Null
    }

    $detailSP.Children.Add((New-Separator)) | Out-Null

    # ── BOTONES DE ACCIÓN ────────────────────────────────────
    $actHdr = New-TextBlock '[ ACCIONES RÁPIDAS ]' 11 $Script:BR.GreenDim $true
    $actHdr.Margin = New-T 0 4 0 6
    $detailSP.Children.Add($actHdr) | Out-Null

    $Script:UI.BtnKill = New-Button '🗡️  Finalizar Proceso' `
        -bg (New-Brush $Script:CLR.RedDark) -fg (New-Brush $Script:CLR.Red) `
        -border (New-Brush $Script:CLR.Red) -h 30 -onClick { Do-KillProcess }
    $detailSP.Children.Add($Script:UI.BtnKill) | Out-Null

    $Script:UI.BtnFolder = New-Button '📁  Abrir Carpeta' -h 30 -onClick { Do-OpenFolder }
    $detailSP.Children.Add($Script:UI.BtnFolder) | Out-Null

    $Script:UI.BtnGoogle = New-Button '🌐  Buscar en Google' `
        -bg (New-Brush $Script:CLR.CyanDark) -fg (New-Brush $Script:CLR.Cyan) `
        -border (New-Brush $Script:CLR.Cyan) -h 30 -onClick { Do-SearchWeb }
    $detailSP.Children.Add($Script:UI.BtnGoogle) | Out-Null

    $Script:UI.BtnTree = New-Button '🌳  Ver Árbol de Procesos' -h 30 -onClick { Do-ViewTree }
    $detailSP.Children.Add($Script:UI.BtnTree) | Out-Null

    $Script:UI.BtnCopy = New-Button '📋  Copiar Info al Portapapeles' -h 30 -onClick { Do-CopyInfo }
    $detailSP.Children.Add($Script:UI.BtnCopy) | Out-Null

    $detailSP.Children.Add((New-Separator)) | Out-Null

    # ── BOTONES DE MARCADO ───────────────────────────────────
    $markHdr = New-TextBlock '[ CLASIFICAR MANUALMENTE ]' 11 $Script:BR.GreenDim $true
    $markHdr.Margin = New-T 0 4 0 6
    $detailSP.Children.Add($markHdr) | Out-Null

    $Script:UI.BtnMarkSafe = New-Button '✅  Marcar como Inofensivo' `
        -bg (New-Brush ([System.Windows.Media.Color]::FromRgb(0,28,10))) `
        -fg (New-Brush $Script:CLR.GreenMid) -border (New-Brush $Script:CLR.GreenMid) `
        -h 28 -onClick { Do-MarkSafe }
    $detailSP.Children.Add($Script:UI.BtnMarkSafe) | Out-Null

    $Script:UI.BtnMarkSusp = New-Button '⚠️  Marcar como Sospechoso' `
        -bg (New-Brush $Script:CLR.YellowDk) -fg (New-Brush $Script:CLR.Yellow) `
        -border (New-Brush $Script:CLR.Yellow) -h 28 -onClick { Do-MarkSuspicious }
    $detailSP.Children.Add($Script:UI.BtnMarkSusp) | Out-Null

    $Script:UI.BtnMarkCrit = New-Button '🔒  Marcar como Crítico (Sistema)' `
        -bg (New-Brush $Script:CLR.CyanDark) -fg (New-Brush $Script:CLR.Cyan) `
        -border (New-Brush $Script:CLR.Cyan) -h 28 -onClick { Do-MarkCritical }
    $detailSP.Children.Add($Script:UI.BtnMarkCrit) | Out-Null

    $Script:UI.BtnUnmark = New-Button '↩️  Quitar Marca Manual' `
        -bg (New-Brush $Script:CLR.GrayDark) -fg $Script:BR.GrayGrn `
        -border $Script:BR.GrayGrn -h 28 -onClick { Do-Unmark }
    $detailSP.Children.Add($Script:UI.BtnUnmark) | Out-Null

    # ══════════════════════════════════════════════════════════
    # FILA 4 – BITÁCORA / LOG
    # ══════════════════════════════════════════════════════════
    $logOuter = [System.Windows.Controls.Border]::new()
    $logOuter.Background = New-Brush $Script:CLR.BgLog
    $logOuter.BorderBrush = $Script:BR.Border
    $logOuter.BorderThickness = New-T 0 1 0 1
    [System.Windows.Controls.Grid]::SetRow($logOuter, 4)
    $root.Children.Add($logOuter) | Out-Null

    $logGrid = [System.Windows.Controls.Grid]::new()
    $logOuter.Child = $logGrid

    $logTitleB = [System.Windows.Controls.Border]::new()
    $logTitleB.Background = New-Brush ([System.Windows.Media.Color]::FromRgb(3,12,3))
    $logTitleB.Width = 120
    $logTitleB.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $logTitleB.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    $logTitleB.Padding = New-T 8 3 8 3
    $logTitleB.BorderBrush = $Script:BR.Border
    $logTitleB.BorderThickness = New-T 0 0 1 1
    $logTitleB.Child = (New-TextBlock '📋 BITÁCORA DE AUDITORÍA' 9 $Script:BR.GreenMid $true)
    $logGrid.Children.Add($logTitleB) | Out-Null

    $logScroll = [System.Windows.Controls.ScrollViewer]::new()
    $logScroll.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $logScroll.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $logScroll.Margin = New-T 0 20 0 0
    $logGrid.Children.Add($logScroll) | Out-Null

    $Script:UI.LogBox = [System.Windows.Controls.TextBox]::new()
    $Script:UI.LogBox.Background = $Script:BR.Transparent
    $Script:UI.LogBox.Foreground = $Script:BR.GreenMid
    $Script:UI.LogBox.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $Script:UI.LogBox.FontSize = 12
    $Script:UI.LogBox.IsReadOnly = $true
    $Script:UI.LogBox.BorderThickness = New-T 0
    $Script:UI.LogBox.AcceptsReturn = $true
    $Script:UI.LogBox.Padding = New-T 8 4 8 4
    $Script:UI.LogBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    $logScroll.Content = $Script:UI.LogBox

    # ══════════════════════════════════════════════════════════
    # FILA 5 – BARRA DE ESTADO
    # ══════════════════════════════════════════════════════════
    $statusBorder = [System.Windows.Controls.Border]::new()
    $statusBorder.Background = New-Brush ([System.Windows.Media.Color]::FromRgb(3,12,3))
    $statusBorder.BorderBrush = $Script:BR.Border
    $statusBorder.BorderThickness = New-T 0 1 0 0
    $statusBorder.Padding = New-T 10 0 10 0
    [System.Windows.Controls.Grid]::SetRow($statusBorder, 5)
    $root.Children.Add($statusBorder) | Out-Null

    $statusGrid = [System.Windows.Controls.Grid]::new()
    $statusGrid.ColumnDefinitions.Add((New-GridColDef 1 ([System.Windows.GridUnitType]::Star)))
    $statusGrid.ColumnDefinitions.Add((New-GridColDef 180))
    $statusBorder.Child = $statusGrid

    $Script:UI.StatusLabel = New-TextBlock 'Listo. Presiona [ESCANEAR PROCESOS] para iniciar análisis.' 10 $Script:BR.GreenMid
    [System.Windows.Controls.Grid]::SetColumn($Script:UI.StatusLabel, 0)
    $statusGrid.Children.Add($Script:UI.StatusLabel) | Out-Null

    $Script:UI.ClockLabel = New-TextBlock (Get-Date -Format 'HH:mm:ss  yyyy-MM-dd') 10 $Script:BR.GrayGrn
    $Script:UI.ClockLabel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    [System.Windows.Controls.Grid]::SetColumn($Script:UI.ClockLabel, 1)
    $statusGrid.Children.Add($Script:UI.ClockLabel) | Out-Null

    # ── TIMERS ────────────────────────────────────────────────
    # Reloj
    $Script:TimerClock = [System.Windows.Threading.DispatcherTimer]::new()
    $Script:TimerClock.Interval = [TimeSpan]::FromSeconds(1)
    $Script:TimerClock.add_Tick({ $Script:UI.ClockLabel.Text = Get-Date -Format 'HH:mm:ss  yyyy-MM-dd' })
    $Script:TimerClock.Start()

    # Auto-refresco
    $Script:TimerAuto = [System.Windows.Threading.DispatcherTimer]::new()
    $Script:TimerAuto.Interval = [TimeSpan]::FromSeconds(30)
    $Script:TimerAuto.add_Tick({ Do-Scan })

    # ── CIERRE ────────────────────────────────────────────────
    $win.add_Closing({
        $Script:TimerClock.Stop()
        $Script:TimerAuto.Stop()
        Write-AuditLog 'PROCESSHUNTER CERRADO'
    })

    $Script:UI.Window = $win
    return $win
}

# ══════════════════════════════════════════════════════════════
# HELPER: Separador visual de toolbar
# ══════════════════════════════════════════════════════════════
function Add-ToolSep {
    $s = [System.Windows.Controls.Separator]::new()
    $s.Width = 1
    $s.Height = 20
    $s.Background = $Script:BR.Border
    $s.Margin = New-T 6 0 6 0
    $s.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    return $s
}

# ══════════════════════════════════════════════════════════════
# LÓGICA DE ACCIONES
# ══════════════════════════════════════════════════════════════
function Do-Scan {
    $Script:UI.StatusLabel.Text = '⏳ Escaneando procesos del sistema...'
    $Script:UI.BtnScan.IsEnabled = $false

    $win = $Script:UI.Window
    $win.Dispatcher.InvokeAsync([Action]{
        try {
            $raw = @(Invoke-ProcessScan)
            $Script:AllProcs = [System.Collections.Generic.List[PSObject]]::new()
            foreach ($p in $raw) { $Script:AllProcs.Add($p) | Out-Null }

            Do-ApplyFilter
            Do-UpdateCountBadges

            $nZ  = @($Script:AllProcs | Where-Object Category -eq 'ZOMBIE').Count
            $nS  = @($Script:AllProcs | Where-Object Category -eq 'SUSPICIOUS').Count
            $nD  = @($Script:AllProcs | Where-Object Category -eq 'DEGRADING').Count
            $nF  = @($Script:AllProcs | Where-Object Category -eq 'FRIKI').Count
            $tot = $Script:AllProcs.Count

            $Script:UI.StatusLabel.Text = "✅ $tot procesos  |  🧟 $nZ zombis  |  ⚠️ $nS sospechosos  |  🔋 $nD degradantes  |  🤖 $nF frikis"
            $Script:UI.LastScanLabel.Text = "🕐 Escaneo: $(Get-Date -Format 'HH:mm:ss')"
            $Script:UI.BtnScan.IsEnabled = $true

            Write-AuditLog "ESCANEO COMPLETADO  Total:$tot  Zombis:$nZ  Sospechosos:$nS"
        } catch {
            $Script:UI.StatusLabel.Text = "❌ Error durante escaneo: $_"
            $Script:UI.BtnScan.IsEnabled = $true
        }
    }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
}

function Do-ApplyFilter {
    $search = if ($Script:UI.SearchBox) { $Script:UI.SearchBox.Text.ToLower().Trim() } else { '' }
    $cat    = $Script:FilterCat

    $filtered = $Script:AllProcs | Where-Object {
        ($cat -eq 'ALL' -or $_.Category -eq $cat) -and
        ($search -eq '' -or
         $_.Name.ToLower().Contains($search) -or
         $_.Owner.ToLower().Contains($search) -or
         $_.PID.ToString().Contains($search) -or
         $_.Path.ToLower().Contains($search))
    }

    $Script:UI.DataGrid.Items.Clear()
    foreach ($p in $filtered) { $Script:UI.DataGrid.Items.Add($p) | Out-Null }

    # Resaltar filtro activo
    foreach ($k in $Script:UI.FilterBtns.Keys) {
        $Script:UI.FilterBtns[$k].Opacity = if ($k -eq $Script:FilterCat) { 1.0 } else { 0.55 }
    }
}

function Do-UpdateCountBadges {
    $Script:UI.FilterCountsSP.Children.Clear()
    $countDefs = @(
        @{ C='ZOMBIE'; Icon='🧟' }
        @{ C='SUSPICIOUS'; Icon='⚠️' }
        @{ C='DEGRADING'; Icon='🔋' }
        @{ C='FRIKI'; Icon='🤖' }
        @{ C='CRITICAL'; Icon='🔒' }
    )
    foreach ($cd in $countDefs) {
        $n = @($Script:AllProcs | Where-Object Category -eq $cd.C).Count
        if ($n -gt 0) {
            $style = $Script:CAT[$cd.C]
            $b = [System.Windows.Controls.Border]::new()
            $b.Background = New-Brush $style.Bg
            $b.BorderBrush = New-Brush $style.Fg
            $b.BorderThickness = New-T 1
            $b.CornerRadius = [System.Windows.CornerRadius]::new(3)
            $b.Margin = New-T 3 0 3 0
            $b.Padding = New-T 6 1 6 1
            $b.Child = (New-TextBlock "$($cd.Icon) $n" 9 (New-Brush $style.Fg))
            $Script:UI.FilterCountsSP.Children.Add($b) | Out-Null
        }
    }
}

function Do-UpdateDetails {
    param($proc)
    $Script:CurrentProc = $proc
    if (-not $proc) { return }

    $cat   = $proc.Category
    $style = $Script:CAT[$cat]

    # Badge
    $Script:UI.CatBadgeText.Text     = "$($style.Icon)  $($style.Label.ToUpper())"
    $Script:UI.CatBadge.Background   = New-Brush $style.Bg
    $Script:UI.CatBadgeText.Foreground = New-Brush $style.Fg

    # Firma (carga en background)
    $pathCopy = $proc.Path
    $win = $Script:UI.Window
    $win.Dispatcher.InvokeAsync([Action]{
        $sig = Get-ProcessSignature $pathCopy
        $sigColor = if ($sig -like '✅*') { $Script:CLR.GreenMid }
                    elseif ($sig -like '⚠️*') { $Script:CLR.Yellow }
                    else { $Script:CLR.Red }
        $Script:UI.DetailFields['Firma'].Text = $sig
        $Script:UI.DetailFields['Firma'].Foreground = New-Brush $sigColor

        $parentStr = Get-ParentProcessName $proc.ParentPID
        $Script:UI.DetailFields['Padre'].Text = $parentStr
    }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null

    # Campos estáticos
    $Script:UI.DetailFields['Nombre'].Text     = $proc.Name
    $Script:UI.DetailFields['PID'].Text        = "$($proc.PID)"
    $Script:UI.DetailFields['Clasificación'].Text = "$($style.Icon) $($style.Label)"
    $Script:UI.DetailFields['Ruta'].Text       = $proc.Path
    $Script:UI.DetailFields['Firma'].Text      = '⏳ Verificando...'
    $Script:UI.DetailFields['Usuario'].Text    = $proc.Owner
    $Script:UI.DetailFields['Padre'].Text      = '⏳ Buscando...'
    $Script:UI.DetailFields['RAM'].Text        = "$($proc.RAM) MB"
    $Script:UI.DetailFields['CPU'].Text        = "$($proc.CPU) s (acumulado)"
    $Script:UI.DetailFields['Inicio'].Text     = $proc.StartTime
    $Script:UI.DetailFields['Hilos'].Text      = "$($proc.Threads)"
    $Script:UI.DetailFields['Handles'].Text    = "$($proc.Handles)"
    $Script:UI.DetailFields['Título'].Text     = if ($proc.WindowTitle) { $proc.WindowTitle } else { '(sin ventana)' }

    # Colores dinámicos según valores
    $ramClr = if ($proc.RAM -gt 500) { $Script:CLR.Red } elseif ($proc.RAM -gt 200) { $Script:CLR.Orange } else { $Script:CLR.White }
    $Script:UI.DetailFields['RAM'].Foreground = New-Brush $ramClr
}

function Do-KillProcess {
    $proc = $Script:CurrentProc
    if (-not $proc) { Show-Msg 'Selecciona un proceso de la lista primero.' 'Información'; return }

    $isCrit = $proc.Category -eq 'CRITICAL'
    $msg = if ($isCrit) {
        "⛔ ADVERTENCIA CRÍTICA`n`n'$($proc.Name)' es un proceso del SISTEMA.`n`nFinalizarlo puede causar inestabilidad o cierre del sistema.`n`n¿Continuar de todos modos?"
    } else {
        "¿Finalizar el proceso '$($proc.Name)'?`n`nPID: $($proc.PID)  |  Tipo: $($proc.Label)`n`nEsta acción no se puede deshacer."
    }
    $icon = if ($isCrit) { [System.Windows.MessageBoxImage]::Warning } else { [System.Windows.MessageBoxImage]::Question }
    $result = [System.Windows.MessageBox]::Show($msg, 'ProcessHunter – Confirmar', [System.Windows.MessageBoxButton]::YesNo, $icon)

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        try {
            Stop-Process -Id $proc.PID -Force -ErrorAction Stop
            Write-AuditLog 'PROCESO FINALIZADO' $proc.Name $proc.PID
            $Script:UI.StatusLabel.Text = "✅ Proceso '$($proc.Name)' (PID:$($proc.PID)) finalizado correctamente."
            Start-Sleep -Milliseconds 400
            Do-Scan
        } catch {
            $errMsg = "No se pudo finalizar '$($proc.Name)': $_"
            Write-AuditLog 'ERROR AL FINALIZAR' $proc.Name $proc.PID
            Show-Msg "❌ $errMsg" 'Error' 'Error'
            $Script:UI.StatusLabel.Text = "❌ $errMsg"
        }
    }
}

function Do-OpenFolder {
    $proc = $Script:CurrentProc
    if (-not $proc -or $proc.Path -eq 'N/A' -or -not $proc.Path) {
        Show-Msg 'Ruta del ejecutable no disponible para este proceso.' 'Sin ruta'; return
    }
    $dir = Split-Path $proc.Path -Parent
    if (Test-Path $dir -ErrorAction SilentlyContinue) {
        Start-Process explorer.exe $dir
        Write-AuditLog 'ABRIR CARPETA' $proc.Name $proc.PID
    } else {
        Show-Msg "Carpeta no encontrada:`n$dir" 'Carpeta no existe' 'Warning'
    }
}

function Do-SearchWeb {
    $proc = $Script:CurrentProc
    if (-not $proc) { return }
    $q = [uri]::EscapeDataString("$($proc.Name) Windows proceso ¿qué es? seguro")
    Start-Process "https://www.google.com/search?q=$q"
    Write-AuditLog 'BUSCAR EN WEB' $proc.Name $proc.PID
}

function Do-ViewTree {
    $proc = $Script:CurrentProc
    if (-not $proc) { return }

    $txt  = "ÁRBOL DE PROCESOS`n"
    $txt += "═" * 55 + "`n"
    $txt += "Proceso: $($proc.Name)  (PID: $($proc.PID))`n"
    $txt += "Tipo:    $($Script:CAT[$proc.Category].Icon) $($proc.Label)`n"
    $txt += "═" * 55 + "`n`n"

    # Padre
    $parentStr = Get-ParentProcessName $proc.ParentPID
    $txt += "┌─ PADRE`n│  └─ $parentStr`n│`n"

    # Proceso actual
    $txt += "├─ PROCESO ACTUAL`n"
    $txt += "│  └─ $($proc.Name) (PID:$($proc.PID))  [$($proc.Label)]`n"
    $txt += "│     RAM: $($proc.RAM) MB  |  CPU: $($proc.CPU) s  |  Hilos: $($proc.Threads)`n"
    $txt += "│     Ruta: $($proc.Path)`n│`n"

    # Hijos
    $children = @($Script:AllProcs | Where-Object { $_.ParentPID -eq $proc.PID })
    $txt += "└─ PROCESOS HIJO ($($children.Count))`n"
    if ($children.Count -gt 0) {
        foreach ($ch in $children) {
            $txt += "   └─ $($ch.Name) (PID:$($ch.PID))  [$($ch.Label)]  RAM:$($ch.RAM)MB`n"
        }
    } else {
        $txt += "   (ninguno)`n"
    }

    # Ventana secundaria
    $tWin = [System.Windows.Window]::new()
    $tWin.Title = "ProcessHunter – Árbol: $($proc.Name)"
    $tWin.Width = 570
    $tWin.Height = 420
    $tWin.Background = $Script:BR.BgMain
    $tWin.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    $tWin.Owner = $Script:UI.Window
    $tWin.ResizeMode = [System.Windows.ResizeMode]::CanResize

    $scr = [System.Windows.Controls.ScrollViewer]::new()
    $scr.Margin = New-T 10
    $tWin.Content = $scr

    $tb = [System.Windows.Controls.TextBox]::new()
    $tb.Text = $txt
    $tb.Background = $Script:BR.Transparent
    $tb.Foreground = $Script:BR.Green
    $tb.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $tb.FontSize = 13
    $tb.IsReadOnly = $true
    $tb.BorderThickness = New-T 0
    $scr.Content = $tb

    $tWin.ShowDialog() | Out-Null
    Write-AuditLog 'VER ÁRBOL' $proc.Name $proc.PID
}

function Do-CopyInfo {
    $proc = $Script:CurrentProc
    if (-not $proc) { return }
    $sig = Get-ProcessSignature $proc.Path
    $info = @"
══════════════════════════════════════════
  PROCESSHUNTER  –  Informe de Proceso
══════════════════════════════════════════
  Nombre      : $($proc.Name)
  PID         : $($proc.PID)
  Tipo        : $($proc.Label)
  Ruta        : $($proc.Path)
  Firma       : $sig
  Usuario     : $($proc.Owner)
  RAM         : $($proc.RAM) MB
  CPU         : $($proc.CPU) s
  Inicio      : $($proc.StartTime)
  Hilos       : $($proc.Threads)
  Handles     : $($proc.Handles)
  Host        : $env:COMPUTERNAME
  Generado    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
══════════════════════════════════════════
"@
    [System.Windows.Clipboard]::SetText($info)
    $Script:UI.StatusLabel.Text = "📋 Información de '$($proc.Name)' copiada al portapapeles."
    Write-AuditLog 'COPIAR INFO' $proc.Name $proc.PID
}

function Do-MarkSafe {
    $proc = $Script:CurrentProc; if (-not $proc) { return }
    $Script:SafePIDs.Add($proc.PID) | Out-Null
    $Script:SuspPIDs.Remove($proc.PID) | Out-Null
    Write-AuditLog 'MARCAR INOFENSIVO' $proc.Name $proc.PID
    $Script:UI.StatusLabel.Text = "✅ '$($proc.Name)' marcado como inofensivo."
    Do-Scan
}

function Do-MarkSuspicious {
    $proc = $Script:CurrentProc; if (-not $proc) { return }
    $Script:SuspPIDs.Add($proc.PID) | Out-Null
    $Script:SafePIDs.Remove($proc.PID) | Out-Null
    Write-AuditLog 'MARCAR SOSPECHOSO' $proc.Name $proc.PID
    $Script:UI.StatusLabel.Text = "⚠️ '$($proc.Name)' marcado como sospechoso."
    Do-Scan
}

function Do-MarkCritical {
    $proc = $Script:CurrentProc; if (-not $proc) { return }
    $Script:CritNames.Add($proc.Name) | Out-Null
    Write-AuditLog 'MARCAR CRÍTICO' $proc.Name $proc.PID
    $Script:UI.StatusLabel.Text = "🔒 '$($proc.Name)' marcado como proceso crítico."
    Do-Scan
}

function Do-Unmark {
    $proc = $Script:CurrentProc; if (-not $proc) { return }
    $Script:SafePIDs.Remove($proc.PID) | Out-Null
    $Script:SuspPIDs.Remove($proc.PID) | Out-Null
    Write-AuditLog 'QUITAR MARCA' $proc.Name $proc.PID
    $Script:UI.StatusLabel.Text = "↩️ Marca eliminada para '$($proc.Name)'."
    Do-Scan
}

function Do-PurgeZombies {
    $zombies = @($Script:AllProcs | Where-Object { $_.Category -eq 'ZOMBIE' })
    if ($zombies.Count -eq 0) {
        Show-Msg "No se encontraron procesos zombi.`nRealiza un escaneo primero." 'Sin zombis'
        return
    }
    $list = ($zombies | ForEach-Object { "  •  $($_.Name)  (PID:$($_.PID))  –  $($_.RAM) MB" }) -join "`n"
    $msg  = "💀 ¿Purgar TODOS los procesos zombi?`n`n$list`n`nTotal: $($zombies.Count) procesos`n`n⚠️ Esta acción no se puede deshacer."
    $r = [System.Windows.MessageBox]::Show($msg, 'ProcessHunter – Purgar Zombis', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($r -eq [System.Windows.MessageBoxResult]::Yes) {
        $ok = 0; $fail = 0
        foreach ($z in $zombies) {
            try {
                Stop-Process -Id $z.PID -Force -ErrorAction Stop
                Write-AuditLog 'ZOMBI PURGADO' $z.Name $z.PID
                $ok++
            } catch { $fail++ }
        }
        $Script:UI.StatusLabel.Text = "💀 Purga completada: $ok eliminados, $fail errores."
        Start-Sleep -Milliseconds 400
        Do-Scan
    }
}

function Do-ToggleAuto {
    $Script:AutoRefreshOn = -not $Script:AutoRefreshOn
    if ($Script:AutoRefreshOn) {
        $Script:TimerAuto.Start()
        $Script:UI.BtnAuto.Content    = '⏱️  AUTO: ON  [30s]'
        $Script:UI.BtnAuto.Foreground = $Script:BR.Green
        Write-AuditLog 'AUTO-REFRESCO ACTIVADO'
    } else {
        $Script:TimerAuto.Stop()
        $Script:UI.BtnAuto.Content    = '⏱️  AUTO: OFF'
        $Script:UI.BtnAuto.Foreground = $Script:BR.GrayGrn
        Write-AuditLog 'AUTO-REFRESCO DESACTIVADO'
    }
}

function Do-Export {
    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Title    = 'Exportar Informe – ProcessHunter'
    $dlg.Filter   = 'Informe HTML (*.html)|*.html|Texto plano (*.txt)|*.txt|CSV (*.csv)|*.csv|JSON (*.json)|*.json'
    $dlg.FileName = "ProcessHunter_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if (-not $dlg.ShowDialog()) { return }

    $ext = [System.IO.Path]::GetExtension($dlg.FileName).ToLower()
    switch ($ext) {
        '.html' { Export-AsHTML $dlg.FileName }
        '.csv'  { Export-AsCSV  $dlg.FileName }
        '.json' { Export-AsJSON $dlg.FileName }
        default { Export-AsTXT  $dlg.FileName }
    }
    $Script:UI.StatusLabel.Text = "📤 Informe exportado: $($dlg.FileName)"
    Write-AuditLog "EXPORTAR INFORME ($ext)" $dlg.FileName
    Show-Msg "✅ Informe exportado correctamente:`n$($dlg.FileName)" 'Exportación exitosa'
}

function Export-AsHTML {
    param([string]$path)
    $rows = $Script:AllProcs | ForEach-Object {
        $s = $Script:CAT[$_.Category]
        $fgHex = '#{0:X2}{1:X2}{2:X2}' -f $s.Fg.R, $s.Fg.G, $s.Fg.B
        "<tr style='color:$fgHex'>
            <td>$($s.Icon) $($s.Label)</td><td>$($_.Name)</td><td>$($_.PID)</td>
            <td>$($_.RAM)</td><td>$($_.CPU)</td><td>$($_.Owner)</td>
            <td>$($_.StartTime)</td><td style='font-size:10px;word-break:break-all'>$($_.Path)</td>
        </tr>"
    }
    $nZ = @($Script:AllProcs | Where-Object Category -eq 'ZOMBIE').Count
    $nS = @($Script:AllProcs | Where-Object Category -eq 'SUSPICIOUS').Count
    $nD = @($Script:AllProcs | Where-Object Category -eq 'DEGRADING').Count
    $nF = @($Script:AllProcs | Where-Object Category -eq 'FRIKI').Count

    @"
<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">
<title>ProcessHunter – Informe $(Get-Date -Format 'yyyy-MM-dd')</title>
<style>
  *{box-sizing:border-box}
  body{background:#050905;color:#00ff46;font-family:Consolas,monospace;margin:0;padding:20px}
  h1{color:#00ff46;font-size:22px;border-bottom:2px solid #005020;padding-bottom:10px;margin-bottom:6px}
  .meta{color:#558855;font-size:11px;margin-bottom:18px}
  .badges{display:flex;gap:14px;margin:14px 0;flex-wrap:wrap}
  .badge{background:#080e08;border:1px solid #005020;border-radius:5px;padding:8px 16px;text-align:center}
  .badge .n{font-size:26px;font-weight:bold;line-height:1}
  .badge .l{font-size:10px;color:#558855;margin-top:3px}
  table{border-collapse:collapse;width:100%;font-size:11px;margin-top:14px}
  th{background:#030f03;color:#00b432;border:1px solid #004015;padding:7px 9px;text-align:left;position:sticky;top:0}
  td{border:1px solid #002810;padding:5px 8px;vertical-align:top}
  tr:hover td{background:rgba(0,255,70,.06)}
</style></head><body>
<h1>🧟 ProcessHunter v$($Script:Version) – Informe de Diagnóstico</h1>
<div class="meta">Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') &nbsp;|&nbsp; Host: $env:COMPUTERNAME &nbsp;|&nbsp; Usuario: $env:USERNAME</div>
<div class="badges">
  <div class="badge"><div class="n" style="color:#00ff46">$nZ</div><div class="l">🧟 Zombis</div></div>
  <div class="badge"><div class="n" style="color:#ffc800">$nS</div><div class="l">⚠️ Sospechosos</div></div>
  <div class="badge"><div class="n" style="color:#ff9100">$nD</div><div class="l">🔋 Degradantes</div></div>
  <div class="badge"><div class="n" style="color:#b932ff">$nF</div><div class="l">🤖 Frikis</div></div>
  <div class="badge"><div class="n" style="color:#00e6e6">$($Script:AllProcs.Count)</div><div class="l">⚙️ Total</div></div>
</div>
<table><thead><tr><th>TIPO</th><th>NOMBRE</th><th>PID</th><th>RAM(MB)</th><th>CPU(s)</th><th>USUARIO</th><th>INICIO</th><th>RUTA</th></tr></thead>
<tbody>$($rows -join '')</tbody></table></body></html>
"@ | Out-File -FilePath $path -Encoding UTF8
}

function Export-AsTXT {
    param([string]$path)
    $lines = @(
        "ProcessHunter v$($Script:Version) – Informe de Procesos",
        ("=" * 80),
        "Fecha  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Host   : $env:COMPUTERNAME   |   Usuario: $env:USERNAME",
        ("=" * 80), ""
    )
    foreach ($p in $Script:AllProcs) {
        $lines += "[$($p.Label.ToUpper().PadRight(11))] $($p.Name.PadRight(28)) PID:$("$($p.PID)".PadRight(7)) RAM:$("$($p.RAM)MB".PadRight(9)) CPU:$($p.CPU)s"
        $lines += "   Ruta: $($p.Path)"
        $lines += "   Usuario: $($p.Owner)   |   Inicio: $($p.StartTime)"
        $lines += ""
    }
    $lines | Out-File -FilePath $path -Encoding UTF8
}

function Export-AsCSV {
    param([string]$path)
    $Script:AllProcs |
        Select-Object Category,Name,PID,RAM,CPU,Owner,StartTime,Threads,Handles,Path |
        Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
}

function Export-AsJSON {
    param([string]$path)
    @{
        Generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Host = $env:COMPUTERNAME
        User = $env:USERNAME
        Processes = @($Script:AllProcs | Select-Object Category,Name,PID,RAM,CPU,Owner,StartTime,Threads,Handles,Path)
    } | ConvertTo-Json -Depth 3 | Out-File -FilePath $path -Encoding UTF8
}

function Show-Msg {
    param([string]$msg, [string]$title = 'ProcessHunter', [string]$type = 'Information')
    $icon = switch ($type) {
        'Warning' { [System.Windows.MessageBoxImage]::Warning }
        'Error'   { [System.Windows.MessageBoxImage]::Error }
        default   { [System.Windows.MessageBoxImage]::Information }
    }
    [System.Windows.MessageBox]::Show($msg, "ProcessHunter – $title", [System.Windows.MessageBoxButton]::OK, $icon) | Out-Null
}

# ══════════════════════════════════════════════════════════════
# PUNTO DE ENTRADA PRINCIPAL
# ══════════════════════════════════════════════════════════════
Write-AuditLog "PROCESSHUNTER INICIADO  v$($Script:Version)"

$window = Build-MainWindow
$window.add_Loaded({ Do-Scan })
$window.ShowDialog() | Out-Null