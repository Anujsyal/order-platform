# Alert Runbooks

Every Prometheus alert links here through its `runbook_url` annotation. Each entry covers what the alert means, how to confirm it, and how to fix it.

Set up your shell first: `export KUBECONFIG=~/.kube/order-platform-<env>`. Install the kubectl Argo Rollouts plugin too; MANUAL-SETUP-GUIDE.md section F has the download command.

**Severity policy**

| Severity | Meaning | Where it goes | Response |
|---|---|---|---|
| `critical` | Users are affected now, or soon will be | Slack critical receiver (`@channel` in prod), repeats every 1h in prod, 2h in staging, 4h in dev | Act now |
| `warning` | Something is degrading or a release needs attention | Slack warning receiver, repeats every 6h | Same working day |
| `info` / Watchdog | Context only | Dropped (`null` receiver) | None |

---

## OrderServiceErrorBudgetBurn

**Meaning:** the order-service 5xx ratio is burning through its 7-day error budget (SLO 99.5%) too fast.
- `critical` means the 7-day budget runs out in roughly 12–28 hours at this rate (14.4x or 6x burn).
- `warning` is a slow leak that will still miss the SLO.

**Check**
1. Open the Grafana dashboard **Order Service - SLO & RED**.
2. Look for an orange **Deployment** marker just before the spike. That is the most common cause.
3. Run:
   ```bash
   kubectl argo rollouts get rollout order-service -n order-service
   kubectl logs -n order-service -l app.kubernetes.io/name=order-service --tail=100 | grep -i error
   ```

**Fix**
- **The spike started with a release:** roll back through Git by reverting the `promote(<env>)` commit in `order-platform-gitops`, or run `kubectl argo rollouts abort order-service -n order-service` for an immediate stop.
- **No release:** check dependencies, node health (Platform Overview dashboard) and recent Kyverno or NetworkPolicy changes.

## OrderServiceLatencyBudgetBurn

**Meaning:** more than 1% of requests take longer than 300ms, faster than the latency SLO allows.

**Check:** look at the latency percentiles panel and the CPU-by-pod panel. CPU throttling at the `1` core limit, or JVM GC pressure (heap panel), are the usual causes.

**Fix:** scale replicas in the env overlay (`/spec/replicas` patch), raise the CPU limit, or roll back a slow release.

## OrderServiceDown

**Meaning:** Prometheus cannot scrape any order-service pod. While this alert fires, the other `OrderService*` alerts are inhibited.

**Check**
```bash
kubectl get pods,rollout -n order-service
kubectl describe pod -n order-service -l app.kubernetes.io/name=order-service | tail -30
kubectl get events -n order-service --sort-by=.lastTimestamp | tail -20
```
Common causes:
- `ImagePullBackOff`: wrong tag, or the Docker Hub repo is private.
- Pods blocked by Kyverno/PSA: check the events.
- `CrashLoopBackOff`: read the logs.
- All nodes down: check the CloudWatch `node-health` alarm.

## OrderServiceTrafficDrop

**Meaning:** request rate is under 50% of the same time yesterday. The service may be fine while its callers can't reach it.

**Check:** `curl http://<node>:30080/api/version` from outside, confirm the NodePort SG rule still matches your IP, and run `kubectl get networkpolicy -n order-service`. In this demo setup, also check that the `traffic-generator` pod is running.

## OrderServiceMemoryNearLimit

**Meaning:** a pod is using more than 90% of its 512Mi limit and will be OOM-killed.

**Fix:** `JAVA_TOOL_OPTIONS` sets `MaxRAMPercentage=75`. If the heap panel shows steady growth, suspect a leak; the in-memory order store grows forever by design. Otherwise raise `limits.memory` in `rollout.yaml`.

## OrderServicePodRestarting

**Check**
```bash
kubectl get pods -n order-service
kubectl logs <pod> -n order-service --previous
kubectl describe pod <pod> -n order-service | grep -A5 "Last State"
```
- `OOMKilled`: see the memory runbook above.
- `Liveness probe failed`: the app is hanging or starting too slowly. Check the `startupProbe` budget.

## ArgoCDAppDegraded

**Meaning:** an Argo CD Application's resources are unhealthy.

**Check:** Argo CD UI (`https://<node>:30443`), open the app, and find the red resource. For `order-service` this is usually an aborted canary (see RolloutAborted) or an image that doesn't exist yet.

## ArgoCDAppOutOfSync

**Meaning:** the cluster differs from Git for more than 30 minutes, or syncs keep failing.

**Check:** Argo CD UI, then the app's **Diff** and **Sync status** (the error message is there). Common causes:
- A CRD is missing (wait or retry).
- A Kyverno Enforce policy rejected the change.
- Someone ran `kubectl edit` by hand; selfHeal should undo that.

## RolloutAborted

**Meaning:** canary analysis failed and Argo Rollouts restored the previous version **automatically**. Users are safe, but the release is bad.

**Check**
```bash
kubectl argo rollouts get rollout order-service -n order-service
kubectl get analysisrun -n order-service
kubectl describe analysisrun -n order-service <latest>   # shows the measured success-rate values
```

**Fix:** the Jenkins pipeline normally reverts the GitOps commit itself. If it didn't (for example the pipeline was aborted), revert the `promote(<env>)` commit by hand so Git matches reality. Fix the code and ship a new build.

## KyvernoPolicyViolations

**Meaning:** a workload broke a platform policy. In dev (Audit) it is only reported; in staging/prod (Enforce) the pod was rejected.

**Check**
```bash
kubectl get policyreport -A
kubectl get policyreport -n <ns> -o yaml | grep -B3 -A8 "result: fail"
```

**Fix:** change the manifest (pinned tag, resources, non-root, labels). Never weaken the policy just to ship.

---

## CloudWatch alarms (email via SNS)

These come from **outside** the cluster, so they still work when the cluster itself is down.

| Composite alarm | Fires when | Action |
|---|---|---|
| `order-platform-<env>-node-health` | Any node fails EC2 status checks | EC2 console, then the instance's **Status checks** tab. A *system* check failure means AWS hardware; t3 instances auto-recover, or stop/start to move hosts. An *instance* check failure means the OS is broken: check **Get system log**. |
| `order-platform-<env>-node-pressure` | CPU > 85% (15m), memory > 90% or root disk > 85% | Open the CloudWatch dashboard `order-platform-<env>-nodes` to see which node. For disk: `sudo crictl rmi --prune`, then check the size of `/var/log`. Suppressed while node-health is firing. |
| `order-platform-shared-node-*` | Same for Jenkins | For disk: `docker system prune -af`. |

Logs live in CloudWatch Logs groups `/order-platform-<env>/nodes` (bootstrap and syslog) and `/order-platform-<env>/k8s-audit` (API audit trail). Example Logs Insights query, "who deleted something":
```
fields @timestamp, user.username, verb, objectRef.resource, objectRef.namespace, objectRef.name
| filter verb = "delete"
| sort @timestamp desc
| limit 50
```
