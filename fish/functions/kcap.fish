function kcap --description "kubectl for da-k8s-amer-prod"
    kubectl --kubeconfig ~/.kube/da-k8s-amer-prod --context AKS-USEast-Analytics-Prod-001-pinniped $argv
end