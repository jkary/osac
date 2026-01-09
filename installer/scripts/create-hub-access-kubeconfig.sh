#!/bin/bash

set -e

server_url=$(
  oc config view --minify --output jsonpath="{.clusters[*].cluster.server}"
)

server_name=${server_url#*.}
server_name=${server_name%%.*}

namespace=$(
  oc config view --minify --output jsonpath="{.contexts[*].context.namespace}"
)

token=$(oc -n "$namespace" extract secret/hub-access --keys token --to - 2>/dev/null)

echo "generating a kubeconfig for hub-access serviceaccount in $namespace namespace on $server_url"

cat <<EOF >kubeconfig.hub-access
apiVersion: v1
clusters:
- cluster:
    server: "$server_url"
  name: "$server_name"
contexts:
- context:
    cluster: "$server_name"
    namespace: "$namespace"
    user: "system:serviceaccount:$namespace:hub-access"
  name: "$server_name"
current-context: "$server_name"
kind: Config
preferences: {}
users:
- name: "system:serviceaccount:$namespace:hub-access"
  user:
    token: "$token"
EOF
