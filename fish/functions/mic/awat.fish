function awat --description "argo workflows for da-k8s-amer-test"
    argo --kubeconfig ~/.kube/da-k8s-amer-test --context AKS-USEast-Analytics-001-pinniped --namespace da-zal-workflows $argv
end