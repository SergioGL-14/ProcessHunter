function ConvertTo-HtmlText {
    <#
    .SYNOPSIS
        Encodes untrusted text for insertion into an HTML text context.
    .OUTPUTS
        System.String. Returns an empty string for null input.
    #>
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Export-AsHTML {
    <#
    .SYNOPSIS
        Writes a ProcessHunter process report as HTML.
    .DESCRIPTION
        Names, paths, users, host metadata, and other process text are HTML encoded
        before being inserted into the document.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Processes,
        [Parameter(Mandatory)][hashtable]$Categories,
        [Parameter(Mandatory)][string]$Version,
        [string]$ComputerName = '',
        [string]$UserName = ''
    )

    $rows = $Processes | ForEach-Object {
        $s = $Categories[$_.Category]
        $fgHex = '#{0:X2}{1:X2}{2:X2}' -f $s.Fg.R, $s.Fg.G, $s.Fg.B
        "<tr style='color:$fgHex'>
            <td>$(ConvertTo-HtmlText "$($s.Icon) $($s.Label)")</td><td>$(ConvertTo-HtmlText $_.Name)</td><td>$($_.PID)</td>
            <td>$(ConvertTo-HtmlText $_.RAM)</td><td>$(ConvertTo-HtmlText $_.CPU)</td><td>$(ConvertTo-HtmlText $_.Owner)</td>
            <td>$(ConvertTo-HtmlText $_.StartTime)</td><td style='font-size:10px;word-break:break-all'>$(ConvertTo-HtmlText $_.Path)</td>
        </tr>"
    }
    $nZ = @($Processes | Where-Object Category -eq 'ZOMBIE').Count
    $nS = @($Processes | Where-Object Category -eq 'SUSPICIOUS').Count
    $nD = @($Processes | Where-Object Category -eq 'DEGRADING').Count
    $nF = @($Processes | Where-Object Category -eq 'FRIKI').Count

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
<h1>🧟 ProcessHunter v$(ConvertTo-HtmlText $Version) – Informe de Diagnóstico</h1>
<div class="meta">Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') &nbsp;|&nbsp; Host: $(ConvertTo-HtmlText $ComputerName) &nbsp;|&nbsp; Usuario: $(ConvertTo-HtmlText $UserName)</div>
<div class="badges">
  <div class="badge"><div class="n" style="color:#00ff46">$nZ</div><div class="l">🧟 Zombis</div></div>
  <div class="badge"><div class="n" style="color:#ffc800">$nS</div><div class="l">⚠️ Sospechosos</div></div>
  <div class="badge"><div class="n" style="color:#ff9100">$nD</div><div class="l">🔋 Degradantes</div></div>
  <div class="badge"><div class="n" style="color:#b932ff">$nF</div><div class="l">🤖 Frikis</div></div>
  <div class="badge"><div class="n" style="color:#00e6e6">$($Processes.Count)</div><div class="l">⚙️ Total</div></div>
</div>
<table><thead><tr><th>TIPO</th><th>NOMBRE</th><th>PID</th><th>RAM(MB)</th><th>CPU(s)</th><th>USUARIO</th><th>INICIO</th><th>RUTA</th></tr></thead>
<tbody>$($rows -join '')</tbody></table></body></html>
"@ | Out-File -FilePath $Path -Encoding UTF8
}
