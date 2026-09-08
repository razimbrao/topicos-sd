# Relatório de Testes — TP1

Preencher com as saídas reais coletadas durante a defesa técnica.

## 1. Provisionamento e rede

- [ ] `vagrant up` conclui as 4 VMs sem erro
- [ ] Cada VM possui interface NAT + host-only (`ip -brief address`)
- [ ] `ping 8.8.8.8` responde (saída externa)
- [ ] `dig google.com` resolve (DNS)

```
(colar saída de scripts/validar-rede.sh)
```

## 2. Proxy reverso e balanceamento

```
(colar saída de curl repetido contra http://192.168.56.10/)
```

## 3. Teste de sobrevivência

| Momento | Linhas em `db.log` | Último registro |
|---|---|---|
| Antes do `destroy` | | |
| Depois do `up` | | |

```
(colar saída de scripts/teste-sobrevivencia.ps1)
```

## 4. Auditoria de segurança

```
(colar saída de scripts/auditar-seguranca.ps1)
```

## 5. Idempotência

Segunda execução consecutiva de `vagrant provision bastion`:

```
(colar o PLAY RECAP — esperado changed=0 em todos os hosts)
```
