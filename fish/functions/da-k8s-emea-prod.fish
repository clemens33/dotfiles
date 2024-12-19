function da-k8s-emea-prod
    set -gx KUBECONFIG ~/.kube/da-k8s-emea-prod
    kubectl config use-context AKS-DEW-Analytics-Prod-001-pinniped
    kubectl config current-context
    kubectl cluster-info
end