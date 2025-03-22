function kcda --description "kubectl for da-k8s-internal"
    kubectl --kubeconfig ~/.kube/da.miccust.dev --context MIC-DA-pinniped $argv
end