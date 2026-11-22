package main

# 1. Disallow mutable :latest tag (Zero-Trust: Tag is not an identity)
deny[msg] {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    endswith(container.image, ":latest")
    msg := sprintf("Container '%v' uses forbidden ':latest' tag. Pin image by '@sha256:' digest.", [container.name])
}

# 2. Enforce non-root execution (Pod Security Standard: Restricted)
deny[msg] {
    input.kind == "Deployment"
    not input.spec.template.spec.securityContext.runAsNonRoot == true
    msg := sprintf("Deployment '%v' must set pod-level securityContext.runAsNonRoot: true.", [input.metadata.name])
}

# 3. Enforce read-only root filesystem
deny[msg] {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not container.securityContext.readOnlyRootFilesystem == true
    msg := sprintf("Container '%v' must set securityContext.readOnlyRootFilesystem: true.", [container.name])
}

# 4. Enforce dropping ALL Linux capabilities
deny[msg] {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not has_drop_all(container)
    msg := sprintf("Container '%v' must drop ALL capabilities (capabilities.drop: ['ALL']).", [container.name])
}

has_drop_all(container) {
    container.securityContext.capabilities.drop[_] == "ALL"
}

# 5. Enforce CPU and Memory limits to prevent Noisy Neighbor / DoS
deny[msg] {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf("Container '%v' must define resources.limits.cpu.", [container.name])
}

deny[msg] {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not container.resources.limits.memory
    msg := sprintf("Container '%v' must define resources.limits.memory.", [container.name])
}
