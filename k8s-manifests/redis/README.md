# Redis Stack - Kubernetes Manifests

## Tổng Quan

Stack này bao gồm **Redis** (in-memory database) và **Redis Sentinel** để xây dựng hệ thống cache/database có tính sẵn sàng cao (HA).

### Vai Trò & Mục Đích

**Redis:**

- In-memory key-value database
- Cache layer cho applications
- Session storage
- Real-time analytics
- Message queue (Pub/Sub)
- Rate limiting
- Leaderboards/Counters

**Redis Sentinel:**

- Monitoring Redis instances
- Automatic failover (chuyển master khi down)
- Configuration provider
- Notification system

---

## Kiến Trúc

```
┌─────────────────────────────────────────────────────┐
│              Redis HA Cluster                       │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │ Redis-0  │  │ Redis-1  │  │ Redis-2  │         │
│  │ (Master) │◄─┤ (Replica)│◄─┤ (Replica)│         │
│  └────┬─────┘  └──────────┘  └──────────┘         │
│       │                                            │
│       │  Monitored by                              │
│       ▼                                            │
│  ┌─────────────────────────────────┐              │
│  │     Redis Sentinel Cluster      │              │
│  │  ┌──────┐ ┌──────┐ ┌──────┐    │              │
│  │  │Sent-0│ │Sent-1│ │Sent-2│    │              │
│  │  └──────┘ └──────┘ └──────┘    │              │
│  └─────────────────────────────────┘              │
│                                                     │
│  Auto Failover: Nếu Master down,                   │
│  Sentinel promote 1 Replica thành Master mới       │
└─────────────────────────────────────────────────────┘
```

**Cấu hình:**

- **Redis**: 3 instances (1 master + 2 replicas)
- **Sentinel**: 3 instances (quorum = 2)
- **Persistence**: RDB + AOF
- **Storage**: Longhorn persistent volumes

---

## Cấu Trúc Files

```
redis/
├── 00-namespace.yaml           # Namespace template
├── 01-configmap.yaml           # Redis + Sentinel configs
├── 02-redis-service.yaml       # Redis services (headless + client + sentinel)
├── 03-redis-statefulset.yaml   # Redis cluster (3 instances)
├── 04-sentinel-statefulset.yaml # Sentinel cluster (3 instances)
├── deploy.sh                   # Deployment script
└── README.md                   # This file
```

### Chi Tiết Từng File

#### `00-namespace.yaml`

- Tạo namespace để isolate Redis stack
- Template: thay `NAMESPACE_NAME` khi deploy

#### `01-configmap.yaml`

**Redis Config:**

- Persistence: RDB snapshots + AOF
- Memory policy: allkeys-lru (evict oldest keys)
- Max memory: 512MB
- Replication settings

**Sentinel Config:**

- Monitor master: `redis-0`
- Quorum: 2 (cần 2/3 sentinels đồng ý để failover)
- Down-after: 5 seconds
- Failover timeout: 10 seconds

#### `02-redis-service.yaml`

- **Headless Service** (`redis`): Cho StatefulSet
- **Client Service** (`redis-client`): Endpoint cho applications
- **Sentinel Service** (`redis-sentinel`): Endpoint cho Sentinel

#### `03-redis-statefulset.yaml`

- 3 Redis instances
- redis-0: Master (initial)
- redis-1, redis-2: Replicas
- Persistent storage: 5Gi per instance
- Init container: Auto-configure replication

#### `04-sentinel-statefulset.yaml`

- 3 Sentinel instances
- Monitor Redis master
- Auto-failover khi master down
- Lightweight (128Mi memory)

---

## Deployment

### Cách 1: Dùng Script (Khuyến nghị)

```bash
# Deploy vào namespace mới
./deploy.sh my-app-redis

# Deploy vào namespace mặc định "redis"
./deploy.sh
```

### Cách 2: Manual với kubectl

```bash
# Set namespace
NAMESPACE="my-app-redis"

# Apply manifests
for file in *.yaml; do
  sed "s/NAMESPACE_NAME/$NAMESPACE/g" "$file" | kubectl apply -f -
done
```

### Cách 3: Dùng Kustomize

```bash
# Tạo kustomization.yaml
cat <<EOF > kustomization.yaml
namespace: my-app-redis
resources:
  - 00-namespace.yaml
  - 01-configmap.yaml
  - 02-redis-service.yaml
  - 03-redis-statefulset.yaml
  - 04-sentinel-statefulset.yaml
EOF

# Apply
kubectl apply -k .
```

---

## Kiểm Tra & Monitoring

### Check Status

```bash
NAMESPACE="my-app-redis"

# Xem tất cả resources
kubectl get all -n $NAMESPACE

# Xem pods
kubectl get pods -n $NAMESPACE

# Xem persistent volumes
kubectl get pvc -n $NAMESPACE

# Xem logs
kubectl logs -n $NAMESPACE redis-0
kubectl logs -n $NAMESPACE redis-sentinel-0
```

### Verify Cluster Health

```bash
NAMESPACE="my-app-redis"

# Check Redis replication
kubectl exec -it -n $NAMESPACE redis-0 -- redis-cli INFO replication

# Check Sentinel status
kubectl exec -it -n $NAMESPACE redis-sentinel-0 -- \
  redis-cli -p 26379 SENTINEL masters

# Get current master
kubectl exec -it -n $NAMESPACE redis-sentinel-0 -- \
  redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster
```

---

## Testing & Usage

### Test Connection

```bash
NAMESPACE="my-app-redis"

# Test ping
kubectl run -it --rm redis-test \
  --image=redis:7.2-alpine \
  --restart=Never \
  -n $NAMESPACE \
  -- redis-cli -h redis-client ping

# Expected output: PONG
```

### Basic Operations

```bash
NAMESPACE="my-app-redis"

# Run interactive redis-cli
kubectl run -it --rm redis-test \
  --image=redis:7.2-alpine \
  --restart=Never \
  -n $NAMESPACE \
  -- redis-cli -h redis-client
```

### Inside redis-cli

```bash
# Set key
SET mykey "Hello Redis"

# Get key
GET mykey

# Set with expiration (60 seconds)
SETEX session:user123 60 "user_data"

# Increment counter
INCR page_views

# Hash operations
HSET user:1000 name "John" email "john@example.com"
HGET user:1000 name

# List operations
LPUSH queue:tasks "task1" "task2"
RPOP queue:tasks

# Pub/Sub
PUBLISH notifications "New message"
SUBSCRIBE notifications
```

---

## Connection Strings

### Từ Cùng Namespace

```
Redis:     redis-client:6379
Sentinel:  redis-sentinel:26379
```

### Từ Namespace Khác

```
Redis:     redis-client.<namespace>.svc.cluster.local:6379
Sentinel:  redis-sentinel.<namespace>.svc.cluster.local:26379
```

### Application Config Examples

**Spring Boot (application.yml):**

```yaml
spring:
  redis:
    sentinel:
      master: mymaster
      nodes:
        - redis-sentinel.my-app-redis.svc.cluster.local:26379
    password: "" # No password by default
```

**Node.js (ioredis):**

```javascript
const Redis = require("ioredis");

// With Sentinel
const redis = new Redis({
  sentinels: [
    { host: "redis-sentinel.my-app-redis.svc.cluster.local", port: 26379 },
  ],
  name: "mymaster",
});

// Direct connection (not recommended for HA)
const redis = new Redis({
  host: "redis-client.my-app-redis.svc.cluster.local",
  port: 6379,
});
```

**Python (redis-py):**

```python
from redis.sentinel import Sentinel

# With Sentinel (recommended)
sentinel = Sentinel([
    ('redis-sentinel.my-app-redis.svc.cluster.local', 26379)
])
master = sentinel.master_for('mymaster', socket_timeout=0.1)
slave = sentinel.slave_for('mymaster', socket_timeout=0.1)

# Direct connection
import redis
r = redis.Redis(
    host='redis-client.my-app-redis.svc.cluster.local',
    port=6379,
    decode_responses=True
)
```

**Go (go-redis):**

```go
import "github.com/go-redis/redis/v8"

// With Sentinel
rdb := redis.NewFailoverClient(&redis.FailoverOptions{
    MasterName:    "mymaster",
    SentinelAddrs: []string{"redis-sentinel.my-app-redis.svc.cluster.local:26379"},
})

// Direct connection
rdb := redis.NewClient(&redis.Options{
    Addr: "redis-client.my-app-redis.svc.cluster.local:6379",
})
```

---

## Configuration

### Resource Limits

**Redis:**

- CPU: 100m request, 500m limit
- Memory: 256Mi request, 512Mi limit
- Storage: 5Gi per instance

**Sentinel:**

- CPU: 50m request, 200m limit
- Memory: 128Mi request, 256Mi limit

### Redis Settings

- **Max Memory**: 512MB
- **Eviction Policy**: allkeys-lru (remove least recently used keys)
- **Persistence**: RDB (snapshots) + AOF (append-only file)
- **RDB Snapshots**:
  - Every 900s if 1+ keys changed
  - Every 300s if 10+ keys changed
  - Every 60s if 10000+ keys changed
- **AOF**: fsync every second

### Tuning (Optional)

Để tăng performance, edit `01-configmap.yaml`:

```yaml
# Tăng max memory
maxmemory 1gb

# Đổi eviction policy
maxmemory-policy volatile-lru  # Only evict keys with TTL

# Disable persistence (cache only)
save ""
appendonly no

# Tăng performance (trade-off: data loss risk)
appendfsync no
```

---

## Failover Testing

### Test Automatic Failover

```bash
NAMESPACE="my-app-redis"

# 1. Check current master
kubectl exec -it -n $NAMESPACE redis-sentinel-0 -- \
  redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster

# 2. Kill master pod
kubectl delete pod redis-0 -n $NAMESPACE

# 3. Wait 10-15 seconds, check new master
kubectl exec -it -n $NAMESPACE redis-sentinel-0 -- \
  redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster

# 4. Verify new master
kubectl exec -it -n $NAMESPACE redis-1 -- redis-cli INFO replication
```

---

## Cleanup

### Xóa Toàn Bộ Stack

```bash
NAMESPACE="my-app-redis"

# Xóa tất cả resources
kubectl delete namespace $NAMESPACE

# Hoặc xóa từng resource
kubectl delete statefulset redis redis-sentinel -n $NAMESPACE
kubectl delete svc redis redis-client redis-sentinel -n $NAMESPACE
kubectl delete configmap redis-config sentinel-config -n $NAMESPACE
kubectl delete pvc -l app=redis -n $NAMESPACE
```

---

## Troubleshooting

### Pods Không Start

```bash
# Check events
kubectl describe pod redis-0 -n $NAMESPACE

# Check logs
kubectl logs redis-0 -n $NAMESPACE

# Check PVC
kubectl get pvc -n $NAMESPACE
```

### Replication Không Hoạt Động

```bash
# Check replication status
kubectl exec -it redis-0 -n $NAMESPACE -- redis-cli INFO replication

# Check replica logs
kubectl logs redis-1 -n $NAMESPACE
```

### Sentinel Không Detect Master

```bash
# Check Sentinel logs
kubectl logs redis-sentinel-0 -n $NAMESPACE

# Check Sentinel config
kubectl exec -it redis-sentinel-0 -n $NAMESPACE -- \
  redis-cli -p 26379 SENTINEL masters
```

### Data Loss Sau Khi Restart

```bash
# Check persistence files
kubectl exec -it redis-0 -n $NAMESPACE -- ls -lh /data

# Verify AOF/RDB enabled
kubectl exec -it redis-0 -n $NAMESPACE -- redis-cli CONFIG GET save
kubectl exec -it redis-0 -n $NAMESPACE -- redis-cli CONFIG GET appendonly
```

---

## Monitoring (Optional)

### Redis Exporter

```bash
# Deploy Prometheus Redis Exporter
kubectl apply -f https://raw.githubusercontent.com/oliver006/redis_exporter/master/contrib/k8s-redis-and-exporter-deployment.yaml
```

### Metrics

```bash
# Get Redis stats
kubectl exec -it redis-0 -n $NAMESPACE -- redis-cli INFO stats

# Get memory usage
kubectl exec -it redis-0 -n $NAMESPACE -- redis-cli INFO memory

# Get connected clients
kubectl exec -it redis-0 -n $NAMESPACE -- redis-cli CLIENT LIST
```

---

## Security (Production)

Để production, nên enable:

1. **Password Authentication**

```yaml
# Add to redis.conf
requirepass your-strong-password
```

2. **TLS/SSL Encryption**
3. **Network Policies**
4. **Disable Dangerous Commands**

```yaml
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG ""
```

---

## Use Cases

### 1. Session Storage

```python
# Store user session
redis.setex(f"session:{session_id}", 3600, json.dumps(user_data))

# Get session
session = json.loads(redis.get(f"session:{session_id}"))
```

### 2. Cache Layer

```python
# Check cache first
cached = redis.get(f"user:{user_id}")
if cached:
    return json.loads(cached)

# Cache miss, get from DB
user = db.get_user(user_id)
redis.setex(f"user:{user_id}", 300, json.dumps(user))
return user
```

### 3. Rate Limiting

```python
# Allow 100 requests per minute
key = f"rate_limit:{user_id}:{minute}"
count = redis.incr(key)
if count == 1:
    redis.expire(key, 60)
if count > 100:
    raise RateLimitExceeded()
```

### 4. Pub/Sub

```python
# Publisher
redis.publish('notifications', json.dumps(message))

# Subscriber
pubsub = redis.pubsub()
pubsub.subscribe('notifications')
for message in pubsub.listen():
    process_notification(message)
```

---

## Tài Liệu Tham Khảo

- [Redis Documentation](https://redis.io/documentation)
- [Redis Sentinel](https://redis.io/topics/sentinel)
- [Redis Best Practices](https://redis.io/topics/best-practices)
- [Redis on Kubernetes](https://redis.io/topics/kubernetes)

---

**Version:** 1.0  
**Redis Version:** 7.2-alpine  
**Last Updated:** 2026-02-08
