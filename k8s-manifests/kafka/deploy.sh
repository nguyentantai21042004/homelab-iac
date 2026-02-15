#!/usr/bin/env bash
# Deploy Kafka stack đầy đủ: namespace → Strimzi operator → Kafka cluster → Kafka UI
# Chạy: ./deploy.sh   hoặc   cd k8s-manifests/kafka && ./deploy.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
NAMESPACE="kafka"

echo "[1/4] Namespace $NAMESPACE..."
kubectl apply -f 00-namespace.yaml

echo "[2/4] Strimzi Kafka Operator (lỗi AlreadyExists cho CRD/ClusterRole là bình thường – bỏ qua)..."
kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n "$NAMESPACE" 2>/dev/null || true

echo "[3/4] Đợi operator Ready (tối đa 120s)..."
if ! kubectl wait --for=condition=available --timeout=120s deployment/strimzi-cluster-operator -n "$NAMESPACE" 2>/dev/null; then
  echo "    Operator chưa ready – kiểm tra: kubectl get pods -n $NAMESPACE -l name=strimzi-cluster-operator"
  read -p "    Tiếp tục apply cluster? [y/N] " -n 1 -r; echo
  [[ $REPLY =~ ^[yY]$ ]] || exit 1
fi

echo "[4/4] Kafka cluster + Kafka UI..."
kubectl apply -f 01-kafka-cluster.yaml
kubectl apply -f 02-kafka-ui.yaml

echo ""
echo "Done. Đợi broker/controller Ready: kubectl get pods -n $NAMESPACE -w"
echo "Kafka bootstrap (external): 172.16.21.202:9094"
echo "Kafka UI: http://172.16.21.203:8080"
