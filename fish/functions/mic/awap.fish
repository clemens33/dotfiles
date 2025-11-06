function awap --description "argo workflows for da-k8s-amer-prod"
    argo --kubeconfig ~/.kube/da-k8s-amer-prod --context AKS-USEast-Analytics-Prod-001-pinniped --namespace da-zal-workflows $argv
end