$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\ProcessHunter.Export.ps1')

if ((ConvertTo-HtmlText '<name & "path">') -ne '&lt;name &amp; &quot;path&quot;&gt;') {
    throw 'El escape HTML no codifica caracteres reservados.'
}
if ((ConvertTo-HtmlText $null) -ne '') {
    throw 'El escape HTML no trata null como texto vacío.'
}

$categories = @{
    NORMAL = @{ Icon = ''; Label = 'Normal'; Fg = [pscustomobject]@{ R = 0; G = 255; B = 70 } }
}
$process = [pscustomobject]@{
    Category = 'NORMAL'; Name = 'x</td><script>alert(1)</script>'; PID = 7; RAM = 1
    CPU = 0; Owner = 'user&admin'; StartTime = 'now'; Path = 'C:\<unsafe>\app.exe'
}
$output = Join-Path $env:TEMP 'ProcessHunter-export-test.html'
try {
    Export-AsHTML -Path $output -Processes @($process) -Categories $categories -Version 'test' `
        -ComputerName 'host<&' -UserName 'user<&'
    $html = Get-Content -LiteralPath $output -Raw
    foreach ($unsafe in @('<script>', 'x</td>', 'user&admin', 'C:\<unsafe>\app.exe')) {
        if ($html.Contains($unsafe)) { throw "Texto sin escapar en HTML: $unsafe" }
    }
    foreach ($safe in @('&lt;script&gt;', 'user&amp;admin', 'C:\&lt;unsafe&gt;\app.exe', 'host&lt;&amp;')) {
        if (-not $html.Contains($safe)) { throw "Falta texto escapado en HTML: $safe" }
    }
} finally {
    Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
}

Write-Output 'PASS: escape y exportación HTML'
