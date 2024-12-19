function kcml --description "kubectl for ml-k8s"
    kubectl --kubeconfig ~/.kube/ai.miccust.dev-new --context MIC-AI-CLUSTER-pinniped $argv
end