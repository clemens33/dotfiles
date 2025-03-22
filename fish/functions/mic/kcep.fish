function kcep --description "kubectl for da-k8s-emea-prod"
    kubectl --kubeconfig ~/.kube/da-k8s-emea-prod --context AKS-DEW-Analytics-Prod-001-pinniped $argv
end