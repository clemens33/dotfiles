# MIC kubectl wrappers

kcml() {
    kubectl --kubeconfig ~/.kube/ai.miccust.dev-new --context MIC-AI-CLUSTER-pinniped "$@"
}

kcda() {
    kubectl --kubeconfig ~/.kube/da.miccust.dev --context MIC-DA-pinniped "$@"
}

kcet() {
    kubectl --kubeconfig ~/.kube/da-k8s-emea-test --context AKS-DEW-Analytics-Test-001-pinniped "$@"
}

kcep() {
    kubectl --kubeconfig ~/.kube/da-k8s-emea-prod --context AKS-DEW-Analytics-Prod-001-pinniped "$@"
}

kcat() {
    kubectl --kubeconfig ~/.kube/da-k8s-amer-test --context AKS-DUS-Analytics-Test-001-pinniped "$@"
}

kcap() {
    kubectl --kubeconfig ~/.kube/da-k8s-amer-prod --context AKS-DUS-Analytics-Prod-001-pinniped "$@"
}
