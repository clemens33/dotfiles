function awda --description "argo workflows for da-k8s-internal"
    argo --kubeconfig ~/.kube/da.miccust.dev --context MIC-DA-pinniped --namespace da-zal-workflows $argv
end