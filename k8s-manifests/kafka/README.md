# Kafka với Strimzi Operator

## Đã Deploy Thành Công!

Kafka cluster đã được deploy với Strimzi Operator trong namespace `kafka`.

> **Lưu ý**: Cluster đang chạy ổn định với KRaft mode (không cần Zookeeper).
> Strimzi 0.50.0 đã hỗ trợ KRaft mặc định, không cần bật Feature Gates thủ công.

## Thông Tin Cluster

- **Kafka Version**: 4.0.1
- **Mode**: KRaft (không cần Zookeeper)
- **Replicas**: 1 broker + 1 controller
- **Storage**: Longhorn persistent volumes

## Access Points

**External (từ máy local):**

- Bootstrap: `172.16.21.202:9094` hoặc `kafka.tantai.dev:9094`
- Kafka UI: `172.16.21.203:8080` hoặc `kafbat.tantai.dev:8080`

**Internal (trong K8s):**

- Bootstrap: `homelab-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092`

## Quick Start

### Sử dụng Makefile (Khuyến nghị)

```bash
# Xem tất cả các lệnh có sẵn
make -C k8s-manifests/kafka-strimzi help

# Kiểm tra status
make -C k8s-manifests/kafka-strimzi status

# Kiểm tra health
make -C k8s-manifests/kafka-strimzi check

# List topics
make -C k8s-manifests/kafka-strimzi list-topics

# Tạo topic mới
make -C k8s-manifests/kafka-strimzi create-topic

# Xem logs
make -C k8s-manifests/kafka-strimzi logs
```

### Test Connection (Manual)

```bash
# Từ máy local (cần kafka CLI tools)
kafka-topics --bootstrap-server 172.16.21.202:9094 --list

# Hoặc exec vào broker pod
kubectl exec -it homelab-kafka-broker-0 -n kafka -- /bin/bash
cd /opt/kafka/bin
./kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Create Topic

```bash
# Via kubectl (recommended)
kubectl apply -f - <<EOF
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: test-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: homelab-kafka
spec:
  partitions: 3
  replicas: 1
EOF

# Via kafka CLI
kafka-topics --bootstrap-server 172.16.21.202:9094 \
  --create --topic test-topic \
  --partitions 3 --replication-factor 1
```

### Produce/Consume Messages

```bash
# Producer
kafka-console-producer --bootstrap-server 172.16.21.202:9094 --topic test-topic

# Consumer
kafka-console-consumer --bootstrap-server 172.16.21.202:9094 \
  --topic test-topic --from-beginning
```

## Files

- `00-namespace.yaml` - Kafka namespace
- `01-kafka-cluster.yaml` - Kafka cluster definition (KafkaNodePools + Kafka CRD)
- `02-kafka-ui.yaml` - Kafka UI deployment
- `check-health.sh` - Script kiểm tra health của cluster
- `Makefile` - Các lệnh tiện ích để quản lý cluster

## Management

### Check Health

```bash
# Chạy script kiểm tra health
./k8s-manifests/kafka-strimzi/check-health.sh

# Hoặc kiểm tra thủ công
kubectl get kafka -n kafka
kubectl get pods -n kafka
kubectl top pod -n kafka
```

### Scale Cluster

```bash
# Scale brokers
kubectl patch kafkanodepool broker -n kafka \
  --type merge -p '{"spec":{"replicas":3}}'

# Scale controllers
kubectl patch kafkanodepool controller -n kafka \
  --type merge -p '{"spec":{"replicas":3}}'
```

### Check Status

```bash
# Cluster status
kubectl get kafka -n kafka

# Pods
kubectl get pods -n kafka

# Topics
kubectl get kafkatopics -n kafka

# Services
kubectl get svc -n kafka
```

### Logs

```bash
# Broker logs
kubectl logs homelab-kafka-broker-0 -n kafka

# Controller logs
kubectl logs homelab-kafka-controller-1 -n kafka

# Operator logs
kubectl logs -n kafka -l name=strimzi-cluster-operator
```

## Cleanup

```bash
# Delete Kafka cluster (keeps PVCs)
kubectl delete kafka homelab-kafka -n kafka
kubectl delete kafkanodepool broker controller -n kafka

# Delete everything including PVCs
kubectl delete namespace kafka
```

## Troubleshooting

Nếu gặp vấn đề, xem file TROUBLESHOOTING.md để biết chi tiết về:

- Feature Gates chưa được bật
- Tài nguyên memory quá thấp
- Phiên bản không tương thích
- Kafka UI không kết nối được
- Storage issues

**Quick checks:**

```bash
# Kiểm tra Feature Gates
kubectl get deployment strimzi-cluster-operator -n kafka -o yaml | grep -A 2 "STRIMZI_FEATURE_GATES"

# Xem logs của operator
kubectl logs -n kafka -l name=strimzi-cluster-operator --tail=50

# Kiểm tra resource usage
kubectl top pod -n kafka
```

---

**Deployed**: 2026-02-08  
**Operator**: Strimzi 0.50.0  
**Kafka**: 4.0.1 (KRaft mode)

## Summary

Kafka cluster đang chạy ổn định với:

- KRaft mode (không cần Zookeeper)
- 1 Controller + 1 Broker
- Longhorn persistent storage
- External access qua LoadBalancer
- Kafka UI để quản lý
- Tài nguyên đã được tối ưu (Controller: 1Gi, Broker: 2Gi)
