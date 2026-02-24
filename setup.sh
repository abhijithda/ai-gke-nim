#!/bin/bash

set -x;

export PROJECT_ID=project-3ed36386-5326-4b6e-b52
export REGION=us-west1
export ZONE=us-west1-b
export CLUSTER_NAME=nim-demo
export NODE_POOL_MACHINE_TYPE=g2-standard-16
export CLUSTER_MACHINE_TYPE=e2-standard-4
export GPU_TYPE=nvidia-l4
export GPU_COUNT=1
export NGC_API_KEY_FILE=./nvapi.txt

: <<'COMMENT'
echo "Creating GKE cluster...";
gcloud container clusters create ${CLUSTER_NAME} \
    --project=${PROJECT_ID} \
    --location=${ZONE} \
    --release-channel=rapid \
    --machine-type=${CLUSTER_MACHINE_TYPE} \
    --num-nodes=1


echo "Creating GPU node pool...";
gcloud container node-pools create gpupool \
    --accelerator type=${GPU_TYPE},count=${GPU_COUNT},gpu-driver-version=latest \
    --project=${PROJECT_ID} \
    --location=${ZONE} \
    --cluster=${CLUSTER_NAME} \
    --machine-type=${NODE_POOL_MACHINE_TYPE} \
    --num-nodes=1
COMMENT

export NGC_CLI_API_KEY=`cat $NGC_API_KEY_FILE`
# echo "Key: $NGC_CLI_API_KEY";

echo "Fetching NIM LLM Helm Chart..."; 
helm fetch https://helm.ngc.nvidia.com/nim/charts/nim-llm-1.3.0.tgz --username='$oauthtoken' --password=$NGC_CLI_API_KEY

echo "Creating a NIM namespace...";
kubectl create namespace nim

echo "Configuring secrets...";
kubectl create secret docker-registry registry-secret --docker-server=nvcr.io --docker-username='$oauthtoken'     --docker-password=$NGC_CLI_API_KEY -n nim

kubectl create secret generic ngc-api --from-literal=NGC_API_KEY=$NGC_CLI_API_KEY -n nim

echo "Setting up NIM Configuration...";
cat <<EOF > nim_custom_value.yaml
image:
  repository: "nvcr.io/nim/meta/llama3-8b-instruct" # container location
  tag: 1.0.0 # NIM version you want to deploy
model:
  ngcAPISecret: ngc-api  # name of a secret in the cluster that includes a key named NGC_CLI_API_KEY and is an NGC API key
persistence:
  enabled: true
imagePullSecrets:
  -   name: registry-secret # name of a secret used to pull nvcr.io images, see https://kubernetes.io/docs/tasks/    configure-pod-container/pull-image-private-registry/
EOF

echo "Lauching NIM deployment...";
helm install my-nim nim-llm-1.3.0.tgz -f nim_custom_value.yaml --namespace nim
# helm install my-nim nim-llm-1.1.2.tgz -f nim_custom_value.yaml --namespace nim

echo "Waiting for 2 mins for pod to be up and running..."
sleep 120

echo "Verifying NIM pods are running...";
kubectl get pods -n nim

echo "Enabling locol host communication / Portforwarding...";
kubectl port-forward service/my-nim-nim-llm 8000:8000 -n nim
