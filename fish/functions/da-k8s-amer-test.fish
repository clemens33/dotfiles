function da-k8s-amer-test
    set -gx KUBECONFIG ~/.kube/da-k8s-amer-test
    kubectl config use-context AKS-USEast-Analytics-001-pinniped
    kubectl config current-context
    kubectl cluster-info
end