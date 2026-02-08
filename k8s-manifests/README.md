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

# Resource Planning & Configuration Guide

## 📊 Tổng Quan Resource Consumption

Bảng này giúp bạn tính toán tài nguyên cần thiết cho K3s cluster.

---

## 🎯 Resource Summary Table

### Redis Stack (High Availability Mode)

| Component    | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage | Total CPU | Total Memory | Total Storage |
| ------------ | -------- | ----------- | --------- | -------------- | ------------ | ------- | --------- | ------------ | ------------- |
| **Redis**    | 3        | 100m        | 500m      | 256Mi          | 512Mi        | 5Gi     | 300m      | 768Mi        | 15Gi          |
| **Sentinel** | 3        | 50m         | 200m      | 128Mi          | 256Mi        | -       | 150m      | 384Mi        | -             |
| **TOTAL**    | 6 pods   | -           | -         | -              | -            | -       | **450m**  | **1.15Gi**   | **15Gi**      |

### Kafka Stack (High Availability Mode)

| Component     | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage   | Total CPU | Total Memory | Total Storage |
| ------------- | -------- | ----------- | --------- | -------------- | ------------ | --------- | --------- | ------------ | ------------- |
| **Kafka**     | 3        | 250m        | 1000m     | 512Mi          | 2Gi          | 10Gi      | 750m      | 1.5Gi        | 30Gi          |
| **Zookeeper** | 3        | 100m        | 500m      | 256Mi          | 512Mi        | 5Gi + 2Gi | 300m      | 768Mi        | 21Gi          |
| **TOTAL**     | 6 pods   | -           | -         | -              | -            | -         | **1050m** | **2.27Gi**   | **51Gi**      |

### n8n Stack (Single Mode)

| Component | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage | Total CPU | Total Memory | Total Storage |
| --------- | -------- | ----------- | --------- | -------------- | ------------ | ------- | --------- | ------------ | ------------- |
| **n8n**   | 1        | 100m        | 1000m     | 256Mi          | 1Gi          | 10Gi    | 100m      | 256Mi        | 10Gi          |
| **TOTAL** | 1 pod    | -           | -         | -              | -            | -       | **100m**  | **256Mi**    | **10Gi**      |

### n8n Stack (Queue Mode - với Redis)

| Component    | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage | Total CPU | Total Memory | Total Storage |
| ------------ | -------- | ----------- | --------- | -------------- | ------------ | ------- | --------- | ------------ | ------------- |
| **n8n**      | 3        | 100m        | 1000m     | 256Mi          | 1Gi          | 10Gi    | 300m      | 768Mi        | 30Gi          |
| **Redis**    | 3        | 100m        | 500m      | 256Mi          | 512Mi        | 5Gi     | 300m      | 768Mi        | 15Gi          |
| **Sentinel** | 3        | 50m         | 200m      | 128Mi          | 256Mi        | -       | 150m      | 384Mi        | -             |
| **TOTAL**    | 9 pods   | -           | -         | -              | -            | -       | **750m**  | **1.92Gi**   | **45Gi**      |

---

## 🖥️ Cluster Sizing Recommendations

### Minimum Cluster (Development/Testing)

**Scenario:** n8n (single) + Redis (HA)

```
Total Resources:
- CPU Request: 550m (0.55 cores)
- Memory Request: 1.4Gi
- Storage: 25Gi

Recommended K3s Nodes:
- 2 nodes x (2 CPU, 4GB RAM, 50GB disk)
- Total: 4 CPU, 8GB RAM, 100GB disk
```

### Medium Cluster (Production - Light Load)

**Scenario:** n8n (single) + Redis (HA) + Kafka (HA)

```
Total Resources:
- CPU Request: 1600m (1.6 cores)
- Memory Request: 3.67Gi
- Storage: 76Gi

Recommended K3s Nodes:
- 3 nodes x (2 CPU, 6GB RAM, 100GB disk)
- Total: 6 CPU, 18GB RAM, 300GB disk
```

### Large Cluster (Production - Heavy Load)

**Scenario:** n8n (queue mode) + Redis (HA) + Kafka (HA)

```
Total Resources:
- CPU Request: 1800m (1.8 cores)
- Memory Request: 4.19Gi
- Storage: 96Gi

Recommended K3s Nodes:
- 3 nodes x (4 CPU, 8GB RAM, 150GB disk)
- Total: 12 CPU, 24GB RAM, 450GB disk
```

---

## ⚙️ Configuration Profiles

### Profile 1: Minimal (Homelab/Testing)

**Use case:** Học tập, testing, demo

**Redis:**

```yaml
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 256Mi
storage: 2Gi
replicas: 1 # Single instance, no HA
```

**Kafka:**

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 1Gi
storage: 5Gi
replicas: 1 # Single broker
```

**n8n:**

```yaml
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
storage: 5Gi
replicas: 1
```

**Total:** ~200m CPU, ~512Mi RAM, ~12Gi storage

---

### Profile 2: Standard (Production - Light)

**Use case:** Đồ án, small business, personal projects

**Redis:** (Giữ nguyên như manifest hiện tại)

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
storage: 5Gi
replicas: 3 # HA mode
```

**Kafka:** (Giữ nguyên)

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
storage: 10Gi
replicas: 3
```

**n8n:** (Giữ nguyên)

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
storage: 10Gi
replicas: 1
```

---

### Profile 3: Performance (Production - Heavy)

**Use case:** High traffic, nhiều workflows, real-time processing

**Redis:**

```yaml
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
storage: 10Gi
replicas: 3
```

**Kafka:**

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
storage: 50Gi
replicas: 3
```

**n8n:**

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
storage: 20Gi
replicas: 3 # Queue mode với Redis
```

**Total:** ~3.6 cores CPU, ~7.5Gi RAM, ~180Gi storage

---

## 🔧 Cách Thay Đổi Resource Configuration

### Method 1: Edit YAML trước khi deploy

**Ví dụ: Giảm resource cho Redis (Minimal profile)**

Edit `k8s-manifests/redis/03-redis-statefulset.yaml`:

```yaml
resources:
  requests:
    cpu: 50m # Giảm từ 100m
    memory: 128Mi # Giảm từ 256Mi
  limits:
    cpu: 250m # Giảm từ 500m
    memory: 256Mi # Giảm từ 512Mi
```

Edit storage:

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      resources:
        requests:
          storage: 2Gi # Giảm từ 5Gi
```

### Method 2: Patch sau khi deploy

```bash
# Patch CPU/Memory
kubectl patch statefulset redis -n redis \
  --type='json' \
  -p='[{
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/cpu",
    "value": "50m"
  }]'

# Restart pods để apply changes
kubectl rollout restart statefulset redis -n redis
```

### Method 3: Edit trực tiếp

```bash
# Edit StatefulSet
kubectl edit statefulset redis -n redis

# Tìm section resources và sửa
# Save và exit → Pods sẽ restart tự động
```

---

## 📈 Monitoring & Tuning

### Check Resource Usage

```bash
# Xem resource usage của pods
kubectl top pods -n redis
kubectl top pods -n kafka
kubectl top pods -n n8n

# Xem resource usage của nodes
kubectl top nodes

# Xem resource requests/limits
kubectl describe node <node-name>
```

### Identify Resource Bottlenecks

```bash
# Pods bị OOMKilled (out of memory)
kubectl get pods -A | grep OOMKilled

# Pods bị Evicted (node hết tài nguyên)
kubectl get pods -A | grep Evicted

# Check events
kubectl get events -A --sort-by='.lastTimestamp'
```

### Tuning Guidelines

**CPU:**

- Request: Minimum CPU cần để pod chạy bình thường
- Limit: Maximum CPU pod có thể dùng (throttle nếu vượt)
- Nếu pod bị CPU throttle: Tăng limit
- Nếu node overcommit: Tăng request

**Memory:**

- Request: Minimum memory để schedule pod
- Limit: Maximum memory (OOMKill nếu vượt)
- Nếu pod bị OOMKilled: Tăng limit
- Nếu memory leak: Fix code, không chỉ tăng limit

**Storage:**

- Longhorn volume có thể expand sau khi tạo
- Không thể shrink (giảm size)

```bash
# Expand PVC
kubectl patch pvc redis-data-redis-0 -n redis \
  -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'
```

---

## 🎯 Recommendations cho Đồ Án

### Scenario 1: Budget Tight (1 VM, 4GB RAM)

**Chỉ deploy n8n + External Postgres:**

```
n8n: 1 replica (100m CPU, 256Mi RAM, 5Gi storage)
Postgres: Trên VM host (không tính vào K3s)

Total K3s: 100m CPU, 256Mi RAM, 5Gi storage
→ Chạy thoải mái trên 1 VM 2 CPU, 4GB RAM
```

### Scenario 2: Standard (3 VMs, 6GB RAM mỗi VM)

**n8n + Redis HA:**

```
n8n: 1 replica
Redis: 3 replicas (HA)
Sentinel: 3 replicas

Total: 550m CPU, 1.4Gi RAM, 25Gi storage
→ Chạy tốt trên 3 VMs x (2 CPU, 6GB RAM)
```

### Scenario 3: Full Stack (3 VMs, 8GB RAM mỗi VM)

**n8n + Redis + Kafka (tất cả HA):**

```
n8n: 1 replica
Redis: 3 replicas
Sentinel: 3 replicas
Kafka: 3 brokers
Zookeeper: 3 nodes

Total: 1600m CPU, 3.67Gi RAM, 76Gi storage
→ Cần 3 VMs x (4 CPU, 8GB RAM, 100GB disk)
```

---

## 💡 Cost Optimization Tips

### 1. Giảm Replicas cho Dev/Test

```yaml
# Thay vì 3 replicas (HA)
replicas: 3

# Dùng 1 replica cho testing
replicas: 1
```

**Tiết kiệm:** ~66% resources

### 2. Dùng Minimal Profile

Áp dụng Profile 1 (Minimal) cho tất cả services.

**Tiết kiệm:** ~50% CPU, ~50% RAM

### 3. Shared Redis

Thay vì mỗi app có Redis riêng, dùng chung 1 Redis cluster.

```yaml
# n8n queue mode
QUEUE_BULL_REDIS_HOST: redis-client.shared-redis.svc.cluster.local

# App khác cũng dùng chung
```

**Tiết kiệm:** Không cần deploy nhiều Redis clusters

### 4. Storage Optimization

```yaml
# Giảm retention cho Kafka
KAFKA_LOG_RETENTION_HOURS: "24" # 1 day thay vì 7 days

# Enable compression
KAFKA_COMPRESSION_TYPE: "gzip"
```

### 5. Disable Unused Features

```yaml
# n8n: Disable execution data nếu không cần
EXECUTIONS_DATA_SAVE_ON_SUCCESS: "none"
EXECUTIONS_DATA_SAVE_ON_ERROR: "all"
```

---

## 📊 Quick Reference Table

| Profile         | Use Case          | Total CPU | Total RAM | Total Storage | Nodes           |
| --------------- | ----------------- | --------- | --------- | ------------- | --------------- |
| **Minimal**     | Testing, Demo     | 200m      | 512Mi     | 12Gi          | 1 node (2C/4G)  |
| **Standard**    | Đồ án, Small Prod | 1600m     | 3.67Gi    | 76Gi          | 3 nodes (2C/6G) |
| **Performance** | Heavy Load        | 3600m     | 7.5Gi     | 180Gi         | 3 nodes (4C/8G) |

---

## 🔍 Troubleshooting Resource Issues

### Pod Pending (Insufficient Resources)

```bash
# Check why pod pending
kubectl describe pod <pod-name> -n <namespace>

# Look for: "Insufficient cpu" or "Insufficient memory"
```

**Solution:**

1. Giảm resource requests
2. Thêm nodes vào cluster
3. Xóa pods không cần thiết

### Node Pressure (High Resource Usage)

```bash
# Check node conditions
kubectl describe node <node-name>

# Look for: MemoryPressure, DiskPressure
```

**Solution:**

1. Evict pods không quan trọng
2. Tăng node resources
3. Add more nodes

### OOMKilled (Out of Memory)

```bash
# Check pod status
kubectl get pods -A | grep OOMKilled

# Check logs before crash
kubectl logs <pod-name> -n <namespace> --previous
```

**Solution:**

1. Tăng memory limit
2. Fix memory leak trong app
3. Enable memory profiling

---

**Last Updated:** 2026-02-08  
**Tested on:** K3s v1.28+, Longhorn v1.5+
