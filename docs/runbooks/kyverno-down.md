# Runbook: Відмова Kyverno Admission Webhook (`kyverno-down`)

## Симптоми
* `kubectl apply` у namespace `zt-apps` зависає по таймауту або падає з помилкою `Internal error occurred: failed calling webhook "validate.kyverno.svc-fail"`.
* Причина: Kyverno працює у режимі **Fail-Closed (`failurePolicy: Fail`)** (див. `platform/kyverno/policies/01-verify-images.yaml`), тому при недоступності контролерів деплой блокується навмисно, щоб не пропустити неперевірені образи.

## 1. Діагностика
Перевірити стан подів та подій Kyverno у namespace `kyverno`:
```bash
kubectl get pods -n kyverno
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=100
kubectl get validatingwebhookconfigurations | grep kyverno
```

## 2. Стандартне відновлення
1. Якщо поди впали через нестачу ресурсів або перезапуск ноди, перевірити `PDB` та перезапустити deployment:
   ```bash
   kubectl rollout restart deployment/kyverno-admission-controller -n kyverno
   kubectl rollout status deployment/kyverno-admission-controller -n kyverno --timeout=120s
   ```
2. Переконатися, що сертифікати вебхуків валідні (`cert-manager`):
   ```bash
   kubectl get certificates -n kyverno
   ```

## 3. Аварійний обхід (Break-Glass, лише інцидент P0)
> **Увага:** НЕ видаляйте `ValidatingWebhookConfiguration` повністю без погодження Security Lead!
1. Якщо Kyverno працює, але зовнішній Sigstore/Rekor тимчасово недоступний для термінового хотфіксу — застосуйте тимчасовий `PolicyException` з обов'язковим TTL (`platform/kyverno/exceptions/01-break-glass-emergency.yaml`), оновивши дату `zero-trust.io/expires-at`.
2. Після вирішення інциденту перевірте аудит-події та видаліть виняток (або дочекайтеся авто-очищення через `00-cleanup-expired-exceptions.yaml`).
