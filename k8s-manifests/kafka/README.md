# Kafka Stack - Kubernetes Manifests

## Tổng Quan

Stack này bao gồm **Apache Kafka** và **Zookeeper** để xây dựng hệ thống message queue/event streaming có khả năng mở rộng cao.

### Vai Trò & Mục Đích

**Apache Kafka:**

- Message broker/Event streaming platform
- Xử lý hàng triệu messages/giây
- Dùng cho: Event-driven architecture, Log aggregation, Real-time analytics, Microservices communication

**Zookeeper:**

- Quản lý metadata của Kafka cluster
- Leader election cho Kafka brokers
- Configuration management
- Service discovery

---

## Kiến Trúc

```
┌─────────────────────────────────────────────────────┐
│                  Kafka Cluster                      │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │ Kafka-0  │  │ Kafka-1  │  │ Kafka-2  │         │
│  │ (Broker) │  │ (Broker) │  │ (Broker) │         │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘         │
│       │             │             │                │
│       └─────────────┴─────────────┘                │
│                     │                              │
│              ┌──────▼──────┐                       │
│              │  Zookeeper  │                       │
│              │   Cluster   │                       │
│              │  (3 nodes)  │                       │
│              └─────────────┘                       │
└─────────────────────────────────────────────────────┘
```

**Cấu hình:**

- **Kafka**: 3 brokers (StatefulSet)
- **Zookeeper**: 3 nodes (StatefulSet)
- **Replication Factor**: 3 (high availability)
- **Min In-Sync Replicas**: 2 (data safety)
- **Storage**: Longhorn persistent volumes

---

## Cấu Trúc Files

```
kafka/
├── 00-namespace.yaml              # Namespace template
├── 01-zookeeper-service.yaml      # Zookeeper services (headless + client)
├── 02-zookeeper-statefulset.yaml  # Zookeeper cluster (3 replicas)
├── 03-kafka-service.yaml          # Kafka services (headless + client)
├── 04-kafka-statefulset.yaml      # Kafka cluster (3 brokers)
├── deploy.sh                      # Deployment script
└── README.md                      # This file
```

### Chi Tiết Từng File

#### `00-namespace.yaml`

- Tạo namespace để isolate Kafka stack
- Template: thay `NAMESPACE_NAME` khi deploy

#### `01-zookeeper-service.yaml`

- **Headless Service** (`zookeeper`): Cho StatefulSet, stable network identity
- **Client Service** (`zookeeper-client`): Endpoint cho Kafka kết nối

#### `02-zookeeper-statefulset.yaml`

- 3 Zookeeper nodes cho HA
- Persistent storage: 5Gi data + 2Gi logs
- Anti-affinity: Mỗi node chạy trên K8s node khác nhau
- Health checks: Liveness + Readiness probes

#### `03-kafka-service.yaml`

- **Headless Service** (`kafka`): Cho StatefulSet
- **Client Service** (`kafka-client`): Endpoint cho applications

#### `04-kafka-statefulset.yaml`

- 3 Kafka brokers cho HA
- Persistent storage: 10Gi per broker
- Auto-create topics enabled
- Replication factor: 3
- Min in-sync replicas: 2

---

## Deployment

### Cách 1: Dùng Script (Khuyến nghị)

```bash
# Deploy vào namespace mới
./deploy.sh my-app-kafka

# Deploy vào namespace mặc định "kafka"
./deploy.sh
```

### Cách 2: Manual với kubectl

```bash
# Set namespace
NAMESPACE="my-app-kafka"

# Apply manifests
for file in *.yaml; do
  sed "s/NAMESPACE_NAME/$NAMESPACE/g" "$file" | kubectl apply -f -
done
```

### Cách 3: Dùng Kustomize

```bash
# Tạo kustomization.yaml
cat <<EOF > kustomization.yaml
namespace: my-app-kafka
resources:
  - 00-namespace.yaml
  - 01-zookeeper-service.yaml
  - 02-zookeeper-statefulset.yaml
  - 03-kafka-service.yaml
  - 04-kafka-statefulset.yaml
EOF

# Apply
kubectl apply -k .
```

---

## Kiểm Tra & Monitoring

### Check Status

```bash
NAMESPACE="my-app-kafka"

# Xem tất cả resources
kubectl get all -n $NAMESPACE

# Xem pods
kubectl get pods -n $NAMESPACE

# Xem persistent volumes
kubectl get pvc -n $NAMESPACE

# Xem logs
kubectl logs -n $NAMESPACE kafka-0
kubectl logs -n $NAMESPACE zookeeper-0
```

### Verify Cluster Health

```bash
NAMESPACE="my-app-kafka"

# Check Zookeeper
kubectl exec -it -n $NAMESPACE zookeeper-0 -- zkCli.sh -server localhost:2181 ls /

# Check Kafka brokers
kubectl exec -it -n $NAMESPACE kafka-0 -- kafka-broker-api-versions --bootstrap-server localhost:9092
```

---

## Testing & Usage

### Test Connection

```bash
NAMESPACE="my-app-kafka"

# Run test pod
kubectl run -it --rm kafka-test \
  --image=confluentinc/cp-kafka:7.5.0 \
  --restart=Never \
  -n $NAMESPACE \
  -- bash
```

### Inside Test Pod

```bash
# List topics
kafka-topics --bootstrap-server kafka-client:9092 --list

# Create topic
kafka-topics --bootstrap-server kafka-client:9092 \
  --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 3

# Describe topic
kafka-topics --bootstrap-server kafka-client:9092 \
  --describe \
  --topic test-topic

# Produce messages
kafka-console-producer --bootstrap-server kafka-client:9092 \
  --topic test-topic

# Consume messages
kafka-console-consumer --bootstrap-server kafka-client:9092 \
  --topic test-topic \
  --from-beginning
```

---

## Connection Strings

### Từ Cùng Namespace

```
Zookeeper: zookeeper-client:2181
Kafka:     kafka-client:9092
```

### Từ Namespace Khác

```
Zookeeper: zookeeper-client.<namespace>.svc.cluster.local:2181
Kafka:     kafka-client.<namespace>.svc.cluster.local:9092
```

### Application Config Examples

**Spring Boot (application.yml):**

```yaml
spring:
  kafka:
    bootstrap-servers: kafka-client.my-app-kafka.svc.cluster.local:9092
    consumer:
      group-id: my-app-group
    producer:
      acks: all
```

**Node.js (KafkaJS):**

```javascript
const { Kafka } = require("kafkajs");

const kafka = new Kafka({
  clientId: "my-app",
  brokers: ["kafka-client.my-app-kafka.svc.cluster.local:9092"],
});
```

**Python (kafka-python):**

```python
from kafka import KafkaProducer, KafkaConsumer

producer = KafkaProducer(
    bootstrap_servers=['kafka-client.my-app-kafka.svc.cluster.local:9092']
)

consumer = KafkaConsumer(
    'my-topic',
    bootstrap_servers=['kafka-client.my-app-kafka.svc.cluster.local:9092'],
    group_id='my-group'
)
```

---

## Configuration

### Resource Limits

**Zookeeper:**

- CPU: 100m request, 500m limit
- Memory: 256Mi request, 512Mi limit
- Storage: 5Gi data + 2Gi logs

**Kafka:**

- CPU: 250m request, 1000m limit
- Memory: 512Mi request, 2Gi limit
- Storage: 10Gi per broker

### Kafka Settings

- **Replication Factor**: 3 (mỗi partition có 3 copies)
- **Min In-Sync Replicas**: 2 (cần ít nhất 2 replicas sync)
- **Log Retention**: 168 hours (7 days)
- **Auto Create Topics**: Enabled
- **Max Message Size**: 1MB (default)

### Tuning (Optional)

Để tăng performance, edit `04-kafka-statefulset.yaml`:

```yaml
# Tăng memory
- name: KAFKA_HEAP_OPTS
  value: "-Xmx2G -Xms2G"

# Tăng retention
- name: KAFKA_LOG_RETENTION_HOURS
  value: "720" # 30 days

# Tăng segment size
- name: KAFKA_LOG_SEGMENT_BYTES
  value: "2147483648" # 2GB
```

---

## Cleanup

### Xóa Toàn Bộ Stack

```bash
NAMESPACE="my-app-kafka"

# Xóa tất cả resources
kubectl delete namespace $NAMESPACE

# Hoặc xóa từng resource
kubectl delete statefulset kafka zookeeper -n $NAMESPACE
kubectl delete svc kafka kafka-client zookeeper zookeeper-client -n $NAMESPACE
kubectl delete pvc -l app=kafka -n $NAMESPACE
kubectl delete pvc -l app=zookeeper -n $NAMESPACE
```

---

## Troubleshooting

### Pods Không Start

```bash
# Check events
kubectl describe pod kafka-0 -n $NAMESPACE

# Check logs
kubectl logs kafka-0 -n $NAMESPACE

# Check PVC
kubectl get pvc -n $NAMESPACE
```

### Kafka Không Kết Nối Được Zookeeper

```bash
# Test Zookeeper từ Kafka pod
kubectl exec -it kafka-0 -n $NAMESPACE -- \
  nc -zv zookeeper-client 2181
```

### Topic Không Replicate

```bash
# Check broker status
kubectl exec -it kafka-0 -n $NAMESPACE -- \
  kafka-broker-api-versions --bootstrap-server localhost:9092

# Check topic config
kubectl exec -it kafka-0 -n $NAMESPACE -- \
  kafka-topics --bootstrap-server localhost:9092 \
  --describe --topic <topic-name>
```

---

## Monitoring (Optional)

### Kafka Exporter

```bash
# Deploy Prometheus Kafka Exporter
kubectl apply -f https://raw.githubusercontent.com/danielqsj/kafka_exporter/master/examples/kubernetes/kafka-exporter.yaml
```

### Metrics Endpoints

- Kafka JMX: Port 9999 (nếu enable)
- Kafka Exporter: Port 9308

---

## Security (Production)

Để production, nên enable:

1. **SASL Authentication**
2. **SSL/TLS Encryption**
3. **ACLs (Access Control Lists)**
4. **Network Policies**

Xem thêm: https://kafka.apache.org/documentation/#security

---

## Tài Liệu Tham Khảo

- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka on Kubernetes Best Practices](https://strimzi.io/docs/operators/latest/overview.html)
- [Confluent Platform](https://docs.confluent.io/)

---

**Version:** 1.0  
**Kafka Version:** 7.5.0 (Confluent Platform)  
**Zookeeper Version:** 7.5.0 (Confluent Platform)  
**Last Updated:** 2026-02-08
