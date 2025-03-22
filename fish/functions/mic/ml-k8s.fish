function ml-k8s
    set -gx KUBECONFIG ~/.kube/ai.miccust.dev-new
    kubectl config use-context MIC-AI-CLUSTER-pinniped
    kubectl config current-context
    kubectl cluster-info
end