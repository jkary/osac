#!/bin/sh
set -e

# Fixed line continuation issue 2025-07-25 v3
# Process the rules file with environment variable substitution
envsubst < /etc/fulfillment-service/rules.yaml > /tmp/rules.yaml

# Build the command arguments
DB_URL="postgres://client@${DB_SERVICE_NAME:-fulfillment-database}:5432/service?sslmode=verify-full&sslcert=/secrets/cert/tls.crt&sslkey=/secrets/cert/tls.key&sslrootcert=/secrets/cert/ca.crt"

# Start the fulfillment service with all required arguments
exec /usr/local/bin/fulfillment-service start server \
    --log-level=debug \
    --log-headers=true \
    --log-bodies=true \
    --db-url="$DB_URL" \
    --grpc-listener-network=unix \
    --grpc-listener-address=/run/sockets/server.socket \
    --grpc-authn-type=jwks \
    --grpc-authn-jwks-url=https://kubernetes.default.svc/openid/v1/jwks \
    --grpc-authn-jwks-ca-file=/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    --grpc-authn-jwks-token-file=/run/secrets/kubernetes.io/serviceaccount/token \
    --grpc-authz-type=rules \
    --grpc-authz-rules-file=/tmp/rules.yaml
