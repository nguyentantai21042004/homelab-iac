# RabbitMQ HA Cluster - Kubernetes Manifests

## Tổng Quan

Stack này triển khai **RabbitMQ** (message broker) với cấu hình High Availability (HA) trên K3s cluster, đảm bảo hệ thống messaging luôn sẵn sàng và không mất dữ liệu.

### Vai Trò & Mục Đích

**RabbitMQ:**

- Message broker cho microservices communication
- Asynchronous task processing (background jobs)
- Event-driven architecture
- Decoupling services
- Load balancing cho workers
- Message persistence và reliability

---

## Kiến Trúc

```
┌─────────────────────────────────────────────────────────┐
│           RabbitMQ HA Cluster (3 Nodes)                 │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ rabbitmq-0   │  │ rabbitmq-1   │  │ rabbitmq-2   │   │
│  │              │◄─┤              │◄─┤              │   │
│  │ Cluster Node │  │ Cluster Node │  │ Cluster Node │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│         │                 │                 │           │
│         └─────────────────┴─────────────────┘           │
│                   Erlang Cluster                        │
│                                                         │
│  Features:                                              │
│  ✓ Quorum Queues - Data replicated across 3 nodes       │
│  ✓ Auto-healing - Tự động recover khi partition         │
│  ✓ Balanced queue distribution                          │
│  ✓ Persistent storage với Longhorn                      │
└─────────────────────────────────────────────────────────┘
```

**Cấu hình:**

- **Nodes**: 3 instances (cluster mode)
- **Persistence**: Longhorn volumes (8Gi per node)
- **Discovery**: Kubernetes peer discovery
- **Partition Handling**: Autoheal
- **Queue Type**: Hỗ trợ Quorum Queues (HA)

---

## Cấu Trúc Files

```
rabbitmq/
├── 00-namespace.yaml       # Namespace template
├── 01-secret.yaml          # Credentials + Erlang Cookie
├── 02-configmap.yaml       # RabbitMQ configuration
├── 03-rbac.yaml            # ServiceAccount + Role + RoleBinding
├── 04-services.yaml        # Headless + Client services
├── 05-statefulset.yaml     # RabbitMQ cluster (3 nodes)
├── 06-ingress.yaml         # Management UI ingress
├── deploy.sh               # Deployment script
└── README.md               # This file
```

### Chi Tiết Từng File

#### `00-namespace.yaml`

- Tạo namespace để isolate RabbitMQ stack
- Template: thay `NAMESPACE_NAME` khi deploy

#### `01-secret.yaml`

**Credentials:**

- Username: `admin`
- Password: `StrongPassword123!` (NÊN ĐỔI trong production)

**Erlang Cookie:**

- Mật khẩu để các node RabbitMQ join cluster
- BẮT BUỘC phải giống nhau trên tất cả nodes
- Nếu khác nhau, cluster sẽ không form được

#### `02-configmap.yaml`

**Cluster Settings:**

- Peer discovery: Kubernetes API
- Partition handling: Autoheal (tự động recover)
- Queue master locator: Balanced (phân tán queue)

**Resource Limits:**

- Disk free limit: 2GB
- Memory watermark: 60% (block publishers khi RAM > 60%)

**Plugins:**

- `rabbitmq_management`: Web UI
- `rabbitmq_peer_discovery_k8s`: K8s discovery
- `rabbitmq_prometheus`: Metrics export

#### `03-rbac.yaml`

- ServiceAccount cho RabbitMQ pods
- Role: Quyền get/list/watch endpoints và pods
- Cần thiết để peer discovery hoạt động

#### `04-services.yaml`

**Headless Service** (`rabbitmq-headless`):

- ClusterIP: None
- Cho StatefulSet discovery
- DNS: `rabbitmq-0.rabbitmq-headless.namespace.svc.cluster.local`

**Client Service** (`rabbitmq`):

- ClusterIP: Load balancer nội bộ
- Endpoint cho applications: `rabbitmq.namespace.svc.cluster.local:5672`
- Session affinity: ClientIP (sticky sessions)

#### `05-statefulset.yaml`

- 3 RabbitMQ nodes
- Pod anti-affinity: Cố gắng chia pods ra các K3s nodes khác nhau
- Init container: Setup config files
- Persistent storage: 8Gi per node (Longhorn)
- Resource limits: 250m-1000m CPU, 512Mi-1Gi RAM

#### `06-ingress.yaml`

- Expose Management UI qua Traefik
- Domain: `rabbitmq.tantai.dev`
- Port: 15672

---

## Deployment

### Cách 1: Dùng Script (Khuyến nghị)

```bash
# Deploy vào namespace mới
./deploy.sh my-app-rabbitmq

# Deploy vào namespace mặc định "rabbitmq"
./deploy.sh
```

### Cách 2: Manual với kubectl

```bash
# Set namespace
NAMESPACE="my-app-rabbitmq"

# Apply manifests theo thứ tự
for file in 00-namespace.yaml 01-secret.yaml 02-configmap.yaml 03-rbac.yaml 04-services.yaml 05-statefulset.yaml 06-ingress.yaml; do
  sed "s/NAMESPACE_NAME/$NAMESPACE/g" "$file" | kubectl apply -f -
done
```

### Cách 3: Dùng Kustomize

```bash
# Tạo kustomization.yaml
cat <<EOF > kustomization.yaml
namespace: my-app-rabbitmq
resources:
  - 00-namespace.yaml
  - 01-secret.yaml
  - 02-configmap.yaml
  - 03-rbac.yaml
  - 04-services.yaml
  - 05-statefulset.yaml
  - 06-ingress.yaml
EOF

# Apply
kubectl apply -k .
```

---

## Kiểm Tra & Monitoring

### Check Status

```bash
NAMESPACE="my-app-rabbitmq"

# Xem tất cả resources
kubectl get all -n $NAMESPACE

# Xem pods (đợi cho đến khi cả 3 pods Running)
kubectl get pods -n $NAMESPACE -w

# Xem persistent volumes
kubectl get pvc -n $NAMESPACE

# Xem logs
kubectl logs -n $NAMESPACE rabbitmq-0 -f
```

### Verify Cluster Health

```bash
NAMESPACE="my-app-rabbitmq"

# Check cluster status
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl cluster_status

# List nodes
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl list_nodes

# Check alarms (nên trống)
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl list_alarms
```

### Access Management UI

**Option 1: Port Forward**

```bash
kubectl port-forward -n $NAMESPACE svc/rabbitmq 15672:15672
```

Truy cập: http://localhost:15672

- Username: `admin`
- Password: `StrongPassword123!`

**Option 2: Ingress (sau khi config DNS)**

- URL: http://rabbitmq.tantai.dev
- Thêm vào `/etc/hosts`: `<TRAEFIK_IP> rabbitmq.tantai.dev`

---

## Testing & Usage

### Test Connection

```bash
NAMESPACE="my-app-rabbitmq"

# Test AMQP connection
kubectl run -it --rm rabbitmq-test \
  --image=rabbitmq:3.13-management-alpine \
  --restart=Never \
  -n $NAMESPACE \
  -- rabbitmqadmin -H rabbitmq -u admin -p StrongPassword123! list queues

# Expected: Hiển thị danh sách queues (có thể trống)
```

### Create Test Queue

```bash
NAMESPACE="my-app-rabbitmq"

# Tạo Quorum Queue (HA)
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- \
  rabbitmqadmin declare queue name=test-queue \
  durable=true \
  arguments='{"x-queue-type":"quorum"}'

# Verify
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- \
  rabbitmqctl list_queues name type
```

### Publish & Consume Messages

```bash
NAMESPACE="my-app-rabbitmq"

# Publish message
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- \
  rabbitmqadmin publish routing_key=test-queue payload="Hello RabbitMQ"

# Consume message
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- \
  rabbitmqadmin get queue=test-queue ackmode=ack_requeue_false
```

---

## Connection Strings

### Từ Cùng Namespace

```
AMQP:       amqp://admin:StrongPassword123!@rabbitmq:5672/
Management: http://rabbitmq:15672
```

### Từ Namespace Khác

```
AMQP:       amqp://admin:StrongPassword123!@rabbitmq.<namespace>.svc.cluster.local:5672/
Management: http://rabbitmq.<namespace>.svc.cluster.local:15672
```

### Application Config Examples

**Spring Boot (application.yml):**

```yaml
spring:
  rabbitmq:
    host: rabbitmq.my-app-rabbitmq.svc.cluster.local
    port: 5672
    username: admin
    password: StrongPassword123!
    virtual-host: /
```

**Node.js (amqplib):**

```javascript
const amqp = require("amqplib");

const connection = await amqp.connect({
  protocol: "amqp",
  hostname: "rabbitmq.my-app-rabbitmq.svc.cluster.local",
  port: 5672,
  username: "admin",
  password: "StrongPassword123!",
  vhost: "/",
});

const channel = await connection.createChannel();
```

**Python (pika):**

```python
import pika

credentials = pika.PlainCredentials('admin', 'StrongPassword123!')
parameters = pika.ConnectionParameters(
    host='rabbitmq.my-app-rabbitmq.svc.cluster.local',
    port=5672,
    virtual_host='/',
    credentials=credentials
)

connection = pika.BlockingConnection(parameters)
channel = connection.channel()
```

**Go (amqp091-go):**

```go
import "github.com/rabbitmq/amqp091-go"

conn, err := amqp091.Dial("amqp://admin:StrongPassword123!@rabbitmq.my-app-rabbitmq.svc.cluster.local:5672/")
if err != nil {
    log.Fatal(err)
}
defer conn.Close()

ch, err := conn.Channel()
if err != nil {
    log.Fatal(err)
}
defer ch.Close()
```

---

## Quorum Queues (Best Practice cho HA)

### Tại Sao Cần Quorum Queues?

**Classic Queue (Mặc định):**

- Dữ liệu chỉ nằm trên 1 node
- Nếu node đó chết → Queue mất tạm thời
- Không đảm bảo HA

**Quorum Queue (Recommended):**

- Dữ liệu replicate ra cả 3 nodes (Raft consensus)
- 1 node chết → 2 node còn lại vẫn serve
- Đảm bảo không mất message

### Tạo Quorum Queue

**Via Management UI:**

1. Vào http://rabbitmq.tantai.dev
2. Tab "Queues" → "Add a new queue"
3. Type: Quorum
4. Durable: Yes

**Via Code (Go):**

```go
args := amqp091.Table{
    "x-queue-type": "quorum",
}

_, err := ch.QueueDeclare(
    "my-ha-queue",  // name
    true,           // durable
    false,          // delete when unused
    false,          // exclusive
    false,          // no-wait
    args,           // arguments
)
```

**Via Code (Python):**

```python
channel.queue_declare(
    queue='my-ha-queue',
    durable=True,
    arguments={'x-queue-type': 'quorum'}
)
```

**Via rabbitmqadmin:**

```bash
kubectl exec -it rabbitmq-0 -n $NAMESPACE -- \
  rabbitmqadmin declare queue name=my-ha-queue \
  durable=true \
  arguments='{"x-queue-type":"quorum"}'
```

---

## Auto Reconnect Logic (Best Practice)

### Tại Sao Cần Auto Reconnect?

Khi 1 node RabbitMQ restart hoặc chết:

- Connection TCP bị ngắt
- Application phải tự động kết nối lại
- Nếu không có logic retry → Application crash

### Go Example (với Retry)

```go
package main

import (
    "log"
    "time"
    amqp "github.com/rabbitmq/amqp091-go"
)

func connectWithRetry(url string) (*amqp.Connection, error) {
    for {
        conn, err := amqp.Dial(url)
        if err == nil {
            log.Println("✓ Connected to RabbitMQ")

            // Listen for connection close
            go func() {
                <-conn.NotifyClose(make(chan *amqp.Error))
                log.Println("✗ Connection lost! Reconnecting...")
            }()

            return conn, nil
        }

        log.Printf("✗ Failed to connect: %v. Retrying in 5s...", err)
        time.Sleep(5 * time.Second)
    }
}

func main() {
    url := "amqp://admin:StrongPassword123!@rabbitmq.my-app-rabbitmq.svc.cluster.local:5672/"

    conn, err := connectWithRetry(url)
    if err != nil {
        log.Fatal(err)
    }
    defer conn.Close()

    // Your application logic here
}
```

### Python Example (với Retry)

```python
import pika
import time
import logging

def connect_with_retry(url):
    while True:
        try:
            connection = pika.BlockingConnection(
                pika.URLParameters(url)
            )
            logging.info("✓ Connected to RabbitMQ")
            return connection
        except Exception as e:
            logging.error(f"✗ Failed to connect: {e}. Retrying in 5s...")
            time.sleep(5)

url = "amqp://admin:StrongPassword123!@rabbitmq.my-app-rabbitmq.svc.cluster.local:5672/"
connection = connect_with_retry(url)
channel = connection.channel()
```

---

## Configuration

### Resource Limits

**Per Node:**

- CPU: 250m request, 1000m limit
- Memory: 512Mi request, 1Gi limit
- Storage: 8Gi (Longhorn)

### RabbitMQ Settings

- **Memory Watermark**: 60% (block publishers khi RAM > 60%)
- **Disk Free Limit**: 2GB
- **Heartbeat**: 60 seconds
- **Channel Max**: 2048
- **Partition Handling**: Autoheal

### Tuning (Optional)

Để tăng performance, edit `02-configmap.yaml`:

```yaml
# Tăng memory limit
vm_memory_high_watermark.relative = 0.8

# Tăng channel limit
channel_max = 4096

# Disable persistence (cache-like behavior, KHÔNG khuyến nghị)
# queue_master_locator = client-local
```

---

## Cluster Testing

### Test Node Failure

```bash
NAMESPACE="my-app-rabbitmq"

# 1. Check cluster status
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl cluster_status

# 2. Kill một node
kubectl delete pod rabbitmq-1 -n $NAMESPACE

# 3. Verify cluster vẫn hoạt động (2/3 nodes)
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl cluster_status

# 4. Đợi pod restart (StatefulSet tự tạo lại)
kubectl get pods -n $NAMESPACE -w

# 5. Verify node rejoin cluster
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl cluster_status
```

### Test Quorum Queue Replication

```bash
NAMESPACE="my-app-rabbitmq"

# 1. Tạo quorum queue
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- \
  rabbitmqadmin declare queue name=test-ha \
  durable=true \
  arguments='{"x-queue-type":"quorum"}'

# 2. Publish messages
for i in {1..100}; do
  kubectl exec -it -n $NAMESPACE rabbitmq-0 -- \
    rabbitmqadmin publish routing_key=test-ha payload="Message $i"
done

# 3. Kill node chứa queue leader
kubectl delete pod rabbitmq-0 -n $NAMESPACE

# 4. Verify messages vẫn còn (consume từ node khác)
kubectl exec -it -n $NAMESPACE rabbitmq-1 -- \
  rabbitmqadmin list queues name messages
```

---

## Monitoring

### Metrics Endpoints

```bash
# Prometheus metrics
curl http://rabbitmq.<namespace>.svc.cluster.local:15692/metrics
```

### Health Checks

```bash
NAMESPACE="my-app-rabbitmq"

# Node health
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmq-diagnostics ping

# Check running
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmq-diagnostics check_running

# Check alarms
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl list_alarms

# Memory usage
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl status | grep memory
```

### Useful Commands

```bash
NAMESPACE="my-app-rabbitmq"

# List queues
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl list_queues name type messages

# List connections
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl list_connections

# List channels
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl list_channels

# List users
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl list_users

# List vhosts
kubectl exec -it -n $NAMESPACE rabbitmq-0 -- rabbitmqctl list_vhosts
```

---

## Cleanup

### Xóa Toàn Bộ Stack

```bash
NAMESPACE="my-app-rabbitmq"

# Xóa namespace (xóa tất cả resources)
kubectl delete namespace $NAMESPACE

# Hoặc xóa từng resource
kubectl delete statefulset rabbitmq -n $NAMESPACE
kubectl delete svc rabbitmq rabbitmq-headless -n $NAMESPACE
kubectl delete configmap rabbitmq-config -n $NAMESPACE
kubectl delete secret rabbitmq-secret -n $NAMESPACE
kubectl delete pvc -l app=rabbitmq -n $NAMESPACE
```

---

## Troubleshooting

### Pods Không Start

```bash
# Check events
kubectl describe pod rabbitmq-0 -n $NAMESPACE

# Check logs
kubectl logs rabbitmq-0 -n $NAMESPACE

# Check PVC
kubectl get pvc -n $NAMESPACE
kubectl describe pvc data-rabbitmq-0 -n $NAMESPACE
```

### Cluster Không Form

```bash
# Check Erlang cookie (phải giống nhau)
kubectl exec -it rabbitmq-0 -n $NAMESPACE -- cat /var/lib/rabbitmq/.erlang.cookie
kubectl exec -it rabbitmq-1 -n $NAMESPACE -- cat /var/lib/rabbitmq/.erlang.cookie

# Check DNS resolution
kubectl exec -it rabbitmq-0 -n $NAMESPACE -- \
  nslookup rabbitmq-1.rabbitmq-headless.$NAMESPACE.svc.cluster.local

# Check cluster status
kubectl exec -it rabbitmq-0 -n $NAMESPACE -- rabbitmqctl cluster_status
```

### Connection Refused

```bash
# Check service endpoints
kubectl get endpoints rabbitmq -n $NAMESPACE

# Check if RabbitMQ is listening
kubectl exec -it rabbitmq-0 -n $NAMESPACE -- netstat -tlnp | grep 5672

# Test connection từ pod khác
kubectl run -it --rm test-pod --image=busybox --restart=Never -n $NAMESPACE -- \
  telnet rabbitmq 5672
```

### Memory/Disk Alarms

```bash
# Check alarms
kubectl exec -it rabbitmq-0 -n $NAMESPACE -- rabbitmqctl list_alarms

# Clear memory alarm (tăng limit hoặc xóa messages)
kubectl exec -it rabbitmq-0 -n $NAMESPACE -- rabbitmqctl set_vm_memory_high_watermark 0.7

# Check disk space
kubectl exec -it rabbitmq-0 -n $NAMESPACE -- df -h /var/lib/rabbitmq
```

---

## Security (Production)

### 1. Đổi Default Password

Edit `01-secret.yaml`:

```yaml
stringData:
  rabbitmq-password: "YOUR-STRONG-PASSWORD-HERE"
  rabbitmq-erlang-cookie: "YOUR-RANDOM-COOKIE-32-CHARS"
```

### 2. Enable TLS

Thêm vào `02-configmap.yaml`:

```yaml
listeners.ssl.default = 5671
ssl_options.cacertfile = /etc/rabbitmq/certs/ca.crt
ssl_options.certfile = /etc/rabbitmq/certs/tls.crt
ssl_options.keyfile = /etc/rabbitmq/certs/tls.key
```

### 3. Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rabbitmq-netpol
  namespace: NAMESPACE_NAME
spec:
  podSelector:
    matchLabels:
      app: rabbitmq
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {} # Chỉ cho phép pods trong cùng namespace
      ports:
        - protocol: TCP
          port: 5672
```

---

## Use Cases

### 1. Async Task Processing

```go
// Producer
ch.Publish("", "tasks", false, false, amqp091.Publishing{
    ContentType: "application/json",
    Body:        []byte(`{"task":"send_email","to":"user@example.com"}`),
})

// Consumer (Worker)
msgs, _ := ch.Consume("tasks", "", false, false, false, false, nil)
for msg := range msgs {
    processTask(msg.Body)
    msg.Ack(false)
}
```

### 2. Event-Driven Architecture

```go
// Publisher
ch.ExchangeDeclare("events", "topic", true, false, false, false, nil)
ch.Publish("events", "user.created", false, false, amqp091.Publishing{
    Body: []byte(`{"user_id":123}`),
})

// Subscriber
ch.QueueBind("email-service", "user.*", "events", false, nil)
```

### 3. Work Queue (Load Balancing)

```go
// Multiple workers consume from same queue
// RabbitMQ automatically distributes messages round-robin
ch.Qos(1, 0, false)  // Prefetch 1 message per worker
msgs, _ := ch.Consume("work-queue", "", false, false, false, false, nil)
```

---

## Tài Liệu Tham Khảo

- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [Quorum Queues](https://www.rabbitmq.com/quorum-queues.html)
- [Clustering Guide](https://www.rabbitmq.com/clustering.html)
- [Kubernetes Peer Discovery](https://www.rabbitmq.com/cluster-formation.html#peer-discovery-k8s)
- [Production Checklist](https://www.rabbitmq.com/production-checklist.html)

---

**Version:** 1.0  
**RabbitMQ Version:** 3.13-management-alpine  
**Last Updated:** 2026-02-12
