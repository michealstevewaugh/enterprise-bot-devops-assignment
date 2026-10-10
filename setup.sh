
#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="demo"
NAMESPACE="demo"
RELEASE_NAME="demo"
IMAGE_NAME="python-demo"
IMAGE_TAG="v2"
INGRESS_VERSION="controller-v1.14.3"

cd "$(dirname "$0")"

echo "Checking prerequisites..."

for cmd in docker kind kubectl helm curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command '$cmd' was not found."
        exit 1
    fi
done

docker info >/dev/null

echo "Checking KIND cluster..."

if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    echo "KIND cluster '$CLUSTER_NAME' already exists."
else
    echo "Creating KIND cluster '$CLUSTER_NAME'..."

    kind create cluster \
      --name "$CLUSTER_NAME" \
      --config - <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
EOF
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

echo "Waiting for KIND nodes to become Ready..."

kubectl wait \
  --for=condition=Ready \
  nodes --all \
  --timeout=180s

echo "KIND cluster is ready."
kubectl get nodes

echo "Installing Ingress NGINX..."

kubectl apply \
  -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VERSION}/deploy/static/provider/kind/deploy.yaml"

echo "Waiting for Ingress NGINX deployment..."

kubectl rollout status deployment/ingress-nginx-controller \
  --namespace ingress-nginx \
  --timeout=300s

echo "Ensuring Ingress Controller runs on the port-mapped control-plane..."

kubectl patch deployment ingress-nginx-controller \
  --namespace ingress-nginx \
  --type merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"}}}}}'

echo "Waiting for Ingress Controller rollout..."

kubectl rollout status deployment/ingress-nginx-controller \
  --namespace ingress-nginx \
  --timeout=300s

kubectl wait \
  --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "Ingress NGINX is ready."
kubectl get pods -n ingress-nginx -o wide
kubectl get ingressclass

echo "Building application Docker image..."

docker build \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  ./service

echo "Loading image into KIND cluster..."

kind load docker-image \
  "${IMAGE_NAME}:${IMAGE_TAG}" \
  --name "$CLUSTER_NAME"

echo "Creating application namespace..."

kubectl create namespace "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying application with Helm..."

helm upgrade --install "$RELEASE_NAME" ./chart \
  --namespace "$NAMESPACE" \
  --set image.repository="$IMAGE_NAME" \
  --set image.tag="$IMAGE_TAG" \
  --wait \
  --timeout 300s

echo "Checking application resources..."

kubectl get pods,svc,ingress -n "$NAMESPACE"

echo "Waiting for application endpoints..."

kubectl wait \
  --namespace "$NAMESPACE" \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/instance="$RELEASE_NAME" \
  --timeout=180s

echo "Verifying application through Ingress..."

curl --fail --silent --show-error \
  --noproxy '*' \
  --retry 12 \
  --retry-delay 5 \
  --retry-connrefused \
  --resolve demo.local:80:127.0.0.1 \
  http://demo.local/

echo
echo "Setup completed successfully."

