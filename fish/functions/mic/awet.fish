function awet --description "argo workflows for da-k8s-emea-test"
    argo --kubeconfig ~/.kube/da-k8s-emea-test --context AKS-DEW-Analytics-01-pinniped --namespace da-zal-workflows $argv
end