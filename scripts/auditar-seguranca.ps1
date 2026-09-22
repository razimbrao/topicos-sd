$vms = @{ bastion = "192.168.56.10"; web1 = "192.168.56.11"; web2 = "192.168.56.12"; db = "192.168.56.20" }
$nmap = "C:\Program Files (x86)\Nmap\nmap.exe"

foreach ($nome in $vms.Keys) {
    $ip = $vms[$nome]
    Write-Host "`n=========== $nome ($ip) ===========" -ForegroundColor Cyan

    Write-Host "`n--- Teste 1: SSH somente por chave (esperado: Permission denied) ---" -ForegroundColor Yellow
    ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no `
        -o BatchMode=yes -o ConnectTimeout=5 "vagrant@$ip" exit

    Write-Host "`n--- Teste 2: login direto de root (esperado: negado) ---" -ForegroundColor Yellow
    ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 "root@$ip" exit

    Write-Host "`n--- Teste 3: varredura de portas (esperado: apenas 22, 80, 443) ---" -ForegroundColor Yellow
    & $nmap -Pn -p 22,80,443,514,3306,8080 $ip
}

Write-Host "`nColete esta saida para o relatorio em docs/." -ForegroundColor Green
