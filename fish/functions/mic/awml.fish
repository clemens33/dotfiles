function awml --description "argo workflows for ml-k8s"
    argo --kubeconfig ~/.kube/ai.miccust.dev-new --context MIC-AI-CLUSTER-pinniped --namespace da-zal-workflows $argv
end