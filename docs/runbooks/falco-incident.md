# Runbook: Реагування на Runtime-інцидент Falco (`falco-incident`)

## Симптоми
* Алерт **Falco / Falcosidekick** у Grafana Loki або Slack із пріоритетом `WARNING` / `ERROR`:
  * `[ZT-ALERT] Unauthorized shell spawned in container` (`sh`, `bash`),
  * `[ZT-ALERT] Package manager execution attempted` (`apt`, `pip`),
  * `[ZT-ALERT] Suspicious read of serviceaccount token` або запис у `/etc`, `/bin`, `/usr`.

## 1. Негайна ізоляція (Containment — перші 60 секунд)
> **Не видаляйте скомпрометований под одразу!** Спочатку заблокуйте мережу та вбийте доступи до БД, зберігши под для форензики.

1. **Мережевий карантин (Cilium):**
   Замініть або зафіксуйте на ураженому поді ізоляцію / видаліть доступ (або перевірте дропи в Hubble):
   ```bash
   hubble observe --pod zt-apps/<POD_NAME> --last 50
   ```
2. **Миттєве відкликання динамічних креденшіалів БД у Vault:**
   ```bash
   kubectl exec -n vault vault-0 -- vault lease revoke -prefix database/creds/orders-rw
   ```
   Ця команда миттєво виконує `pg_terminate_backend` та `DROP ROLE` у PostgreSQL — викрадені логін/пароль перестають працювати за < 1 секунду.

## 2. Збір доказів (Forensics)
1. Зняти логи скомпрометованого пода, Falco та аудит-лог Vault:
   ```bash
   kubectl logs -n zt-apps <POD_NAME> > incident-pod.log
   kubectl logs -n falco -l app.kubernetes.io/name=falco --since=15m > incident-falco.log
   ```
2. Зафіксувати точний `@sha256` образ пода та за потреби внести його в `security/revoked-digests.yaml` (політика `deny-revoked-digests` заблокує повторний запуск цього образу в кластері).

## 3. Відновлення (Eradication & Recovery)
Після збереження логів видаліть скомпрометований под, щоб `Deployment` розгорнув чистий екземпляр з новими динамічними креденшіалами VSO:
```bash
kubectl delete pod -n zt-apps <POD_NAME>
```
