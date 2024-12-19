function kcet --description "kubectl for da-k8s-emea-test"
    kubectl --kubeconfig ~/.kube/da-k8s-emea-test --context AKS-DEW-Analytics-01-pinniped $argv
end