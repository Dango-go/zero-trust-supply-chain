# Runbook: Запечатаний стан Vault HA (`vault-sealed`)

## Симптоми
* Поди `vault-0`, `vault-1`, `vault-2` у namespace `vault` перебувають у статусі `Running`, але `READY 0/1`.
* `Vault Secrets Operator (VSO)` у логах повертає `503 Vault is sealed`.
* Нові динамічні паролі PostgreSQL не видаються (`zt-orders` не проходить `/readyz` після закінчення TTL або рестарту).

## 1. Діагностика
Перевірити статус Raft-кластера Vault:
```bash
kubectl exec -n vault vault-0 -- vault status
kubectl logs -n vso -l app.kubernetes.io/name=vault-secrets-operator --tail=50
```
Якщо у виводі `Sealed: true`, кластер потрібно розпечатати (unseal).

## 2. Процедура відновлення (Unseal)
1. **Автоматично (якщо ключі збережені локально у `.vault-init.json`):**
   ```bash
   ./scripts/setup-vault.sh
   ```
2. **Вручну для кожної репліки Raft (`vault-0`, `vault-1`, `vault-2`):**
   Ввести 3 з 5 Shamir-ключів:
   ```bash
   for pod in vault-0 vault-1 vault-2; do
     kubectl exec -n vault "$pod" -- vault operator unseal <UNSEAL_KEY_1>
     kubectl exec -n vault "$pod" -- vault operator unseal <UNSEAL_KEY_2>
     kubectl exec -n vault "$pod" -- vault operator unseal <UNSEAL_KEY_3>
   done
   ```

## 3. Перевірка після Unseal
1. Переконатися, що всі 3 поди перейшли у `READY 1/1` та Raft має лідера:
   ```bash
   kubectl get pods -n vault
   ```
2. Перевірити, що VSO успішно відновив синхронізацію `VaultDynamicSecret` у `zt-apps`:
   ```bash
   kubectl get vaultdynamicsecret -n zt-apps
   ```
