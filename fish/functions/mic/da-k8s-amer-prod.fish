function da-k8s-amer-prod
    set -gx KUBECONFIG ~/.kube/da-k8s-amer-prod
    kubectl config use-context AKS-USEast-Analytics-Prod-001-pinniped
    kubectl config current-context
    kubectl cluster-info
end