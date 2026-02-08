# Kubernetes Manifests - Kafka & Redis Stacks

## Tổng Quan

Thư mục này chứa các Kubernetes manifests để deploy **Kafka** và **Redis** vào bất kỳ namespace nào trong K3s cluster.

### Đặc Điểm

**Dynamic Namespace**: Deploy vào namespace bất kỳ  
**Private Only**: ClusterIP services, không expose ra ngoài  
**High Availability**: Multi-replica với auto-failover  
**Persistent Storage**: Dùng Longhorn volumes  
**Production Ready**: Best practices configuration  
**Easy to Use**: Deploy scripts included

---

## Cấu Trúc

```
k8s-manifests/
├── kafka/                    # Kafka + Zookeeper stack
│   ├── 00-namespace.yaml
│   ├── 01-zookeeper-service.yaml
│   ├── 02-zookeeper-statefulset.yaml
│   ├── 03-kafka-service.yaml
│   ├── 04-kafka-statefulset.yaml
│   ├── deploy.sh
│   └── README.md
│
├── redis/                    # Redis + Sentinel stack
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-redis-service.yaml
│   ├── 03-redis-statefulset.yaml
│   ├── 04-sentinel-statefulset.yaml
│   ├── deploy.sh
│   └── README.md
│
└── README.md                 # This file
```

---

## Use Cases

### Kafka Stack

**Khi nào dùng:**

- Event-driven architecture
- Microservices communication
- Log aggregation
- Real-time data streaming
- Message queue với high throughput

**Ví dụ:**

- User events tracking
- Order processing pipeline
- Log collection từ nhiều services
- Real-time analytics

### Redis Stack

**Khi nào dùng:**

- Caching layer
- Session storage
- Rate limiting
- Real-time leaderboards
- Pub/Sub messaging
- Temporary data storage

**Ví dụ:**

- Cache API responses
- Store user sessions
- Rate limit API requests
- Real-time notifications
- Shopping cart data

---

## Quick Start

### Deploy Kafka

```bash
cd kafka
./deploy.sh my-app-kafka

# Hoặc deploy vào namespace mặc định "kafka"
./deploy.sh
```

### Deploy Redis

```bash
cd redis
./deploy.sh my-app-redis

# Hoặc deploy vào namespace mặc định "redis"
./deploy.sh
```

### Deploy Cả 2 Vào Cùng Namespace

```bash
# Deploy Kafka
cd kafka
sed "s/NAMESPACE_NAME/my-app/g" *.yaml | kubectl apply -f -

# Deploy Redis
cd ../redis
sed "s/NAMESPACE_NAME/my-app/g" *.yaml | kubectl apply -f -
```

---

## So Sánh Kafka vs Redis

| Feature            | Kafka                         | Redis                      |
| ------------------ | ----------------------------- | -------------------------- |
| **Type**           | Message Broker / Event Stream | In-Memory Database / Cache |
| **Persistence**    | Disk-based (durable)          | Memory + Disk (optional)   |
| **Throughput**     | Very High (millions/sec)      | Extremely High (sub-ms)    |
| **Use Case**       | Event streaming, Logs         | Cache, Sessions, Counters  |
| **Data Retention** | Long-term (days/weeks)        | Short-term (seconds/hours) |
| **Message Order**  | Guaranteed (per partition)    | Not guaranteed (Pub/Sub)   |
| **Replication**    | Multi-replica                 | Master-Replica + Sentinel  |
| **Query**          | Sequential read               | Key-value lookup           |

---

## Architecture Overview

### Kafka Stack

```
Applications
    ↓
kafka-client.namespace.svc.cluster.local:9092
    ↓
┌─────────────────────────────────┐
│  Kafka Cluster (3 brokers)     │
│  ├─ kafka-0 (Leader)            │
│  ├─ kafka-1 (Follower)          │
│  └─ kafka-2 (Follower)          │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│  Zookeeper Cluster (3 nodes)   │
│  ├─ zookeeper-0                 │
│  ├─ zookeeper-1                 │
│  └─ zookeeper-2                 │
└─────────────────────────────────┘
```

### Redis Stack

```
Applications
    ↓
redis-client.namespace.svc.cluster.local:6379
    ↓
┌─────────────────────────────────┐
│  Redis Cluster                  │
│  ├─ redis-0 (Master)            │
│  ├─ redis-1 (Replica)           │
│  └─ redis-2 (Replica)           │
└─────────────────────────────────┘
    ↓ monitored by
┌─────────────────────────────────┐
│  Sentinel Cluster (3 nodes)    │
│  ├─ sentinel-0                  │
│  ├─ sentinel-1                  │
│  └─ sentinel-2                  │
│  Auto-failover on master down   │
└─────────────────────────────────┘
```

---

## Connection Examples

### Kafka Connection

**From same namespace:**

```
kafka-client:9092
```

**From different namespace:**

```
kafka-client.my-app-kafka.svc.cluster.local:9092
```

**Spring Boot:**

```yaml
spring:
  kafka:
    bootstrap-servers: kafka-client.my-app-kafka.svc.cluster.local:9092
```

### Redis Connection

**From same namespace:**

```
redis-client:6379
```

**From different namespace:**

```
redis-client.my-app-redis.svc.cluster.local:6379
```

**Spring Boot:**

```yaml
spring:
  redis:
    host: redis-client.my-app-redis.svc.cluster.local
    port: 6379
```

---

## Resource Requirements

### Kafka Stack

| Component | Replicas   | CPU (req/limit)   | Memory (req/limit) | Storage   |
| --------- | ---------- | ----------------- | ------------------ | --------- |
| Zookeeper | 3          | 100m / 500m       | 256Mi / 512Mi      | 5Gi + 2Gi |
| Kafka     | 3          | 250m / 1000m      | 512Mi / 2Gi        | 10Gi      |
| **Total** | **6 pods** | **1050m / 4500m** | **2.25Gi / 7.5Gi** | **51Gi**  |

### Redis Stack

| Component | Replicas   | CPU (req/limit)  | Memory (req/limit)   | Storage  |
| --------- | ---------- | ---------------- | -------------------- | -------- |
| Redis     | 3          | 100m / 500m      | 256Mi / 512Mi        | 5Gi      |
| Sentinel  | 3          | 50m / 200m       | 128Mi / 256Mi        | -        |
| **Total** | **6 pods** | **450m / 2100m** | **1.125Gi / 2.25Gi** | **15Gi** |

### Combined (Kafka + Redis)

- **Total Pods**: 12
- **Total CPU**: 1500m request / 6600m limit
- **Total Memory**: 3.375Gi request / 9.75Gi limit
- **Total Storage**: 66Gi

---

## Monitoring & Health Checks

### Check All Stacks

```bash
# List all namespaces with Kafka/Redis
kubectl get ns -l app.kubernetes.io/component=messaging
kubectl get ns -l app.kubernetes.io/component=cache

# Check all pods
kubectl get pods -A | grep -E "kafka|redis|zookeeper|sentinel"

# Check all PVCs
kubectl get pvc -A | grep -E "kafka|redis|zookeeper"
```

### Health Check Commands

**Kafka:**

```bash
kubectl exec -it kafka-0 -n <namespace> -- \
  kafka-topics --bootstrap-server localhost:9092 --list
```

**Redis:**

```bash
kubectl exec -it redis-0 -n <namespace> -- \
  redis-cli ping
```

---

## Cleanup

### Xóa Một Stack

```bash
# Xóa Kafka
kubectl delete namespace my-app-kafka

# Xóa Redis
kubectl delete namespace my-app-redis
```

### Xóa Tất Cả Stacks

```bash
# Xóa tất cả namespaces có label
kubectl delete ns -l app.kubernetes.io/component=messaging
kubectl delete ns -l app.kubernetes.io/component=cache
```

---

## Customization

### Thay Đổi Resource Limits

Edit StatefulSet files:

```yaml
resources:
  requests:
    cpu: 500m # Tăng CPU
    memory: 1Gi # Tăng Memory
  limits:
    cpu: 2000m
    memory: 4Gi
```

### Thay Đổi Storage Size

Edit volumeClaimTemplates:

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      resources:
        requests:
          storage: 20Gi # Tăng storage
```

### Thay Đổi Replicas

Edit StatefulSet:

```yaml
spec:
  replicas: 5 # Tăng số replicas
```

---

## Security Best Practices

### 1. Network Policies

Tạo NetworkPolicy để restrict traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kafka-network-policy
  namespace: my-app-kafka
spec:
  podSelector:
    matchLabels:
      app: kafka
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: my-app
```

### 2. Resource Quotas

Giới hạn resources per namespace:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: kafka-quota
  namespace: my-app-kafka
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    persistentvolumeclaims: "10"
```

### 3. Pod Security

Enable Pod Security Standards:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app-kafka
  labels:
    pod-security.kubernetes.io/enforce: restricted
```

---

## Documentation

- [Kafka Stack README](kafka/README.md) - Chi tiết về Kafka deployment
- [Redis Stack README](redis/README.md) - Chi tiết về Redis deployment

---

## Notes

- **Namespace Isolation**: Mỗi application nên có namespace riêng
- **Private Only**: Services chỉ accessible trong cluster
- **Persistent Data**: Data được lưu trong Longhorn volumes
- **High Availability**: Multi-replica với auto-failover
- **Production Ready**: Đã config best practices

---

**Version:** 1.0  
**Last Updated:** 2026-02-08  
**Maintained by:** Homelab Infrastructure Team
