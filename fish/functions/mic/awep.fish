function awep --description "argo workflows for da-k8s-emea-prod"
    argo --kubeconfig ~/.kube/da-k8s-emea-prod --context AKS-DEW-Analytics-Prod-001-pinniped --namespace da-zal-workflows $argv
end