function da-k8s-internal
    set -gx KUBECONFIG ~/.kube/da.miccust.dev
    kubectl config use-context MIC-DA-pinniped
    kubectl config current-context
    kubectl cluster-info
end