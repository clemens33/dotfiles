function kcat --description "kubectl for da-k8s-amer-test"
    kubectl --kubeconfig ~/.kube/da-k8s-amer-test --context AKS-USEast-Analytics-001-pinniped $argv
end