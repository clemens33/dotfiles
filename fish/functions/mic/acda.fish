function acda --description "argocd for da-k8s-internal"
    # Set environment for this cluster
    set -lx KUBECONFIG /home/ckriech/.kube/da.miccust.dev
    set -l context MIC-DA-pinniped
    
    # Get admin password from secret
    set -l password (kubectl --kubeconfig $KUBECONFIG --context $context get secret argocd-initial-admin-secret -n argo -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    if test -z "$password"
        echo "Error: Could not retrieve admin password from secret"
        return 1
    end
    
    # Always try to login (it's quick if already logged in)
    echo "Connecting to Argo CD (internal)..."
    argocd --port-forward --port-forward-namespace argo --kube-context $context login localhost:8080 --username admin --password $password --insecure >/dev/null 2>&1
    
    # Execute the actual command
    argocd --port-forward --port-forward-namespace argo --kube-context $context $argv
end