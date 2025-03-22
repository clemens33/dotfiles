function da-k8s-emea-test
    set -gx KUBECONFIG ~/.kube/da-k8s-emea-test
    kubectl config use-context AKS-DEW-Analytics-01-pinniped
    kubectl config current-context
    kubectl cluster-info
end