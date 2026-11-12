$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $raiz "data\dados_persistentes\logs"
Push-Location (Join-Path $raiz "vagrant")

try {
    Write-Host "`n[1/4] Estado ANTES da destruicao" -ForegroundColor Cyan
    $antes = Get-ChildItem $logs -Filter *.log | ForEach-Object {
        [PSCustomObject]@{ Arquivo = $_.Name; Linhas = (Get-Content $_.FullName | Measure-Object -Line).Lines }
    }
    $antes | Format-Table
    $marcador = (Get-Content (Join-Path $logs "db.log") -Tail 1)
    Write-Host "Ultimo registro antes do destroy: $marcador"

    Write-Host "`n[2/4] Simulacao de desastre: vagrant destroy -f db" -ForegroundColor Red
    vagrant destroy -f db

    Write-Host "`n[3/4] Recuperacao automatizada: vagrant up db" -ForegroundColor Yellow
    vagrant up db
    Write-Host "Reaplicando o playbook no no reconstruido..."
    vagrant provision bastion

    Write-Host "`n[4/4] Auditoria de integridade" -ForegroundColor Cyan
    $depois = Get-ChildItem $logs -Filter *.log | ForEach-Object {
        [PSCustomObject]@{ Arquivo = $_.Name; Linhas = (Get-Content $_.FullName | Measure-Object -Line).Lines }
    }
    $depois | Format-Table

    if (Select-String -Path (Join-Path $logs "db.log") -SimpleMatch $marcador -Quiet) {
        Write-Host "[APROVADO] O registro anterior ao destroy continua presente." -ForegroundColor Green
        Write-Host "O estado sobreviveu a aniquilacao da logica computacional."
    } else {
        Write-Host "[REPROVADO] Continuidade dos logs perdida - verifique o synced_folder." -ForegroundColor Red
    }
}
finally { Pop-Location }
