# Policy gate for rendered Kubernetes manifests (scripts/promote.sh):
#   kustomize build overlays/<env> > rendered.yaml
#   conftest test rendered.yaml -p policies/kubernetes
# Runs in CI *before* the change reaches Git. Kyverno enforces similar rules
# again inside the cluster (defence in depth).
package main

import rego.v1

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job", "Rollout"}

pod_spec := input.spec.template.spec if input.kind in workload_kinds

pod_spec := input.spec if input.kind == "Pod"

containers contains c if some c in pod_spec.containers

containers contains c if some c in pod_spec.initContainers

resource_id := sprintf("%s/%s", [input.kind, input.metadata.name])

# ---------------------------------------------------------------- Images

pinned(image) if contains(image, "@sha256:")

pinned(image) if {
	not contains(image, "@")
	parts := split(image, "/")
	last := parts[count(parts) - 1]
	contains(last, ":")
	not endswith(last, ":latest")
}

deny contains msg if {
	some c in containers
	not pinned(c.image)
	msg := sprintf("%s: container %q must use a pinned image tag (not latest/untagged): %s", [resource_id, c.name, c.image])
}

# ---------------------------------------------------------------- Resources

deny contains msg if {
	some c in containers
	some field in ["requests.cpu", "requests.memory", "limits.memory"]
	parts := split(field, ".")
	not c.resources[parts[0]][parts[1]]
	msg := sprintf("%s: container %q must set resources.%s", [resource_id, c.name, field])
}

# ---------------------------------------------------------------- Security context

runs_as_non_root(c) if c.securityContext.runAsNonRoot == true

runs_as_non_root(c) if {
	pod_spec.securityContext.runAsNonRoot == true
	not c.securityContext.runAsNonRoot == false
}

deny contains msg if {
	some c in containers
	not runs_as_non_root(c)
	msg := sprintf("%s: container %q must run as non-root", [resource_id, c.name])
}

deny contains msg if {
	some c in containers
	not c.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("%s: container %q must set allowPrivilegeEscalation: false", [resource_id, c.name])
}

deny contains msg if {
	some c in containers
	not c.securityContext.readOnlyRootFilesystem == true
	msg := sprintf("%s: container %q must set readOnlyRootFilesystem: true", [resource_id, c.name])
}

deny contains msg if {
	some c in containers
	c.securityContext.privileged == true
	msg := sprintf("%s: container %q must not be privileged", [resource_id, c.name])
}

# ---------------------------------------------------------------- Health

# Anything that serves traffic (declares ports) needs probes.
deny contains msg if {
	some c in pod_spec.containers
	count(object.get(c, "ports", [])) > 0
	some probe in ["readinessProbe", "livenessProbe"]
	not c[probe]
	msg := sprintf("%s: container %q exposes ports and must define %s", [resource_id, c.name, probe])
}

# ---------------------------------------------------------------- Services

deny contains msg if {
	input.kind == "Service"
	input.spec.type == "LoadBalancer"
	msg := sprintf("Service/%s: LoadBalancer services are not allowed in this platform", [input.metadata.name])
}
