# n8n Stack - Kubernetes Manifests

## Tổng Quan

Stack này triển khai **n8n** (workflow automation platform) lên K3s cluster với:

- **External Postgres Database** (chạy trên VM riêng)
- **Longhorn Persistent Storage** (cho binary files, uploads)
- **Traefik Ingress** (HTTPS với Let's Encrypt)

### Vai Trò & Mục Đích

**n8n:**

- Workflow automation platform (tương tự Zapier, Make.com)
- Kết nối APIs, tự động hóa tasks
- Dùng cho: CI/CD pipelines, Data sync, Notifications, Business automation

**Kiến trúc:**

- Database: External Postgres (high availability, không bị ảnh hưởng bởi Pod lifecycle)
- Storage: Longhorn PVC (cho files, custom nodes)
- Networking: Traefik IngressRoute (HTTPS, Let's Encrypt)

---

## Kiến Trúc

```
┌─────────────────────────────────────────────────────────┐
│                    Internet (HTTPS)                     │
└────────────────────┬────────────────────────────────────┘
                     │
              ┌──────▼──────┐
              │   Traefik   │ (Ingress Controller)
              │  (Port 443) │
              └──────┬──────┘
                     │
              ┌──────▼──────┐
              │  n8n Pod    │
              │  (Port 5678)│
              └──┬───────┬──┘
                 │       │
        ┌────────▼──┐ ┌──▼─────────────┐
        │ Longhorn  │ │ External       │
        │ PVC (10Gi)│ │ Postgres VM    │
        │ (Files)   │ │ (Database)     │
        └───────────┘ └────────────────┘
```

**Cấu hình:**

- **n8n**: 1 replica (single mode) - Có thể scale với Redis Queue mode
- **Database**: External Postgres trên VM riêng
- **Storage**: Longhorn 10Gi cho files/uploads
- **Ingress**: Traefik với HTTPS/TLS

---

## Cấu Trúc Files

```
n8n/
├── 00-namespace.yaml       # Namespace template
├── 01-secret.yaml          # Credentials (DB password, encryption key)
├── 02-pvc.yaml             # Longhorn persistent volume
├── 03-service.yaml         # ClusterIP service
├── 04-deployment.yaml      # n8n deployment
├── 05-ingress.yaml         # Traefik IngressRoute (HTTPS)
├── deploy.sh               # Deployment script
└── README.md               # This file
```

---

## Deployment

### Phase 1: Chuẩn Bị Database (Trên VM Postgres)

**SSH vào VM Postgres:**

```bash
sudo -u postgres psql
```

**Tạo Database & User:**

```sql
-- Tạo user riêng cho n8n
CREATE USER n8n_user WITH PASSWORD 'StrongPassword123!';

-- Tạo database
CREATE DATABASE n8n_db;

-- Cấp quyền
GRANT ALL PRIVILEGES ON DATABASE n8n_db TO n8n_user;

-- Kết nối vào database
\c n8n_db

-- Cấp quyền schema
GRANT ALL ON SCHEMA public TO n8n_user;
```

**Cấu hình Network Access:**

1. Sửa `postgresql.conf`:

```bash
sudo nano /etc/postgresql/*/main/postgresql.conf
```

Đảm bảo: `listen_addresses = '*'`

2. Sửa `pg_hba.conf`:

```bash
sudo nano /etc/postgresql/*/main/pg_hba.conf
```

Thêm dòng cho phép K3s nodes kết nối:

```
# Allow K3s cluster (adjust IP range to match your network)
host    n8n_db          n8n_user        192.168.1.0/24          scram-sha-256
host    n8n_db          n8n_user        10.42.0.0/16            scram-sha-256
```

3. Restart Postgres:

```bash
sudo systemctl restart postgresql
```

4. Test connection từ K3s node:

```bash
psql -h 192.168.1.100 -U n8n_user -d n8n_db
```

---

### Phase 2: Generate Encryption Key

**CRITICAL:** Encryption key mã hóa tất cả credentials trong n8n (OAuth tokens, API keys, passwords).
**Mất key = mất tất cả connections!**

```bash
# Generate encryption key
docker run --rm n8nio/n8n n8n encryption-key-gen

# Output example: n8n-encryption-key-abc123def456...
# Copy và lưu key này vào Secret
```

---

### Phase 3: Cấu Hình Manifests

**1. Update Secret (`01-secret.yaml`):**

```bash
# Edit secret
nano 01-secret.yaml
```

Thay đổi:

- `DB_PASSWORD`: Password của user `n8n_user` (từ Phase 1)
- `N8N_ENCRYPTION_KEY`: Key vừa generate (từ Phase 2)

**2. Update Deployment (`04-deployment.yaml`):**

Sửa các dòng có comment `# <--- CHANGE`:

- `N8N_HOST`: Domain của bạn (vd: `n8n.example.com`)
- `WEBHOOK_URL`: Webhook URL (vd: `https://n8n.example.com/`)
- `DB_POSTGRESDB_HOST`: IP của VM Postgres (vd: `192.168.1.100`)

**3. Update IngressRoute (`05-ingress.yaml`):**

Sửa:

- `Host()`: Domain của bạn
- `certResolver`: Tên cert resolver trong Traefik config (thường là `le`, `letsencrypt`, hoặc `myresolver`)

---

### Phase 4: Deploy to K3s

**Cách 1: Dùng Script (Khuyến nghị)**

```bash
# Make script executable
chmod +x deploy.sh

# Deploy vào namespace "n8n"
./deploy.sh

# Hoặc deploy vào namespace tùy chỉnh
./deploy.sh my-n8n
```

**Cách 2: Manual với kubectl**

```bash
NAMESPACE="n8n"

# Apply manifests
for file in *.yaml; do
  sed "s/NAMESPACE_NAME/$NAMESPACE/g" "$file" | kubectl apply -f -
done
```

---

## Kiểm Tra & Monitoring

### Check Deployment Status

```bash
NAMESPACE="n8n"

# Xem tất cả resources
kubectl get all -n $NAMESPACE

# Xem pods
kubectl get pods -n $NAMESPACE -w

# Xem logs (quan trọng để check DB connection)
kubectl logs -f deployment/n8n -n $NAMESPACE

# Xem PVC status
kubectl get pvc -n $NAMESPACE

# Xem Longhorn volume
kubectl get pv | grep n8n
```

### Verify Database Connection

```bash
# Check logs for successful DB connection
kubectl logs deployment/n8n -n $NAMESPACE | grep -i postgres

# Should see: "Successfully connected to database"
```

### Check Ingress

```bash
# Xem IngressRoute
kubectl get ingressroute -n $NAMESPACE

# Describe để xem details
kubectl describe ingressroute n8n-ingress -n $NAMESPACE
```

---

## DNS & Access

### Cấu Hình DNS

**Option 1: Public Domain (Recommended for production)**

Trỏ A record của domain về IP public của Traefik LoadBalancer:

```
n8n.example.com  →  A  →  <PUBLIC_IP>
```

**Option 2: Local Network (Testing)**

Trỏ domain về IP LAN của Traefik:

```
n8n.local.example.com  →  A  →  192.168.1.x
```

Hoặc thêm vào `/etc/hosts`:

```
192.168.1.x  n8n.example.com
```

### Cloudflare Tunnel (Nếu không có Public IP)

Nếu mạng nhà không có Public IP, dùng Cloudflare Tunnel:

```bash
# Deploy cloudflared trong K3s
kubectl apply -f https://raw.githubusercontent.com/cloudflare/cloudflared/master/examples/kubernetes/cloudflared.yaml

# Hoặc chạy trên VM riêng
cloudflared tunnel --url http://n8n.n8n.svc.cluster.local:5678
```

---

## Testing

### Test 1: Health Check

```bash
# Từ bên ngoài cluster
curl https://n8n.example.com/healthz

# Từ trong cluster
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl http://n8n.n8n.svc.cluster.local:5678/healthz
```

### Test 2: Webhook

1. Truy cập n8n UI: `https://n8n.example.com`
2. Tạo workflow mới
3. Thêm **Webhook** node
4. Copy Webhook URL (Production URL)
5. Test với curl:

```bash
curl -X POST https://n8n.example.com/webhook/test-webhook \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello n8n!"}'
```

### Test 3: Database Persistence

```bash
# Tạo workflow trong n8n UI
# Xóa pod
kubectl delete pod -l app=n8n -n n8n

# Đợi pod mới lên
kubectl get pods -n n8n -w

# Truy cập lại n8n → Workflow vẫn còn (data trong Postgres)
```

---

## Configuration

### Resource Limits

**n8n Pod:**

- CPU: 100m request, 1000m limit
- Memory: 256Mi request, 1Gi limit
- Storage: 10Gi (Longhorn PVC)

### Tuning (Optional)

**Tăng resources cho workload nặng:**

Edit `04-deployment.yaml`:

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

**Enable execution data pruning:**

Uncomment trong `04-deployment.yaml`:

```yaml
- name: EXECUTIONS_DATA_PRUNE
  value: "true"
- name: EXECUTIONS_DATA_MAX_AGE
  value: "168" # Keep 7 days
```

---

## Scaling (Queue Mode)

Để chạy nhiều replicas (high availability), cần Redis:

### Deploy Redis

```bash
# Sử dụng Redis manifest trong repo này
cd ../redis
./deploy.sh n8n-redis
```

### Update n8n Deployment

Thêm vào `04-deployment.yaml`:

```yaml
env:
  - name: EXECUTIONS_MODE
    value: "queue"
  - name: QUEUE_BULL_REDIS_HOST
    value: "redis-client.n8n-redis.svc.cluster.local"
  - name: QUEUE_BULL_REDIS_PORT
    value: "6379"
```

Tăng replicas:

```yaml
spec:
  replicas: 3 # Chạy 3 pods
```

---

## Cleanup

### Xóa Toàn Bộ Stack

```bash
NAMESPACE="n8n"

# Xóa namespace (xóa tất cả resources)
kubectl delete namespace $NAMESPACE

# Hoặc xóa từng resource
kubectl delete deployment n8n -n $NAMESPACE
kubectl delete service n8n -n $NAMESPACE
kubectl delete ingressroute n8n-ingress -n $NAMESPACE
kubectl delete pvc n8n-pvc -n $NAMESPACE
kubectl delete secret n8n-secret -n $NAMESPACE
```

**Lưu ý:** Database trên Postgres VM không bị xóa. Để xóa:

```bash
sudo -u postgres psql
DROP DATABASE n8n_db;
DROP USER n8n_user;
```

---

## Troubleshooting

### Pod Không Start

```bash
# Check events
kubectl describe pod -l app=n8n -n n8n

# Check logs
kubectl logs -f deployment/n8n -n n8n

# Check PVC
kubectl get pvc -n n8n
kubectl describe pvc n8n-pvc -n n8n
```

### Không Kết Nối Được Database

**Triệu chứng:** Logs hiện `ECONNREFUSED` hoặc `Connection timeout`

**Giải pháp:**

1. Test connection từ n8n pod:

```bash
kubectl exec -it deployment/n8n -n n8n -- sh
apk add postgresql-client
psql -h 192.168.1.100 -U n8n_user -d n8n_db
```

2. Check Postgres logs:

```bash
# Trên VM Postgres
sudo tail -f /var/log/postgresql/postgresql-*.log
```

3. Check firewall:

```bash
# Trên VM Postgres
sudo ufw status
sudo ufw allow from 192.168.1.0/24 to any port 5432
```

### Webhook Không Hoạt Động

**Triệu chứng:** Webhook URL không nhận được requests

**Giải pháp:**

1. Check IngressRoute:

```bash
kubectl get ingressroute -n n8n
kubectl describe ingressroute n8n-ingress -n n8n
```

2. Check Traefik logs:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

3. Test từ trong cluster:

```bash
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl http://n8n.n8n.svc.cluster.local:5678/healthz
```

### Lost Encryption Key

**Triệu chứng:** Không thể decrypt credentials, tất cả connections bị lỗi

**Giải pháp:**

- **KHÔNG CÓ CÁCH NÀO KHÔI PHỤC!**
- Phải tạo lại tất cả connections từ đầu
- **Backup encryption key ngay sau khi generate!**

```bash
# Backup secret
kubectl get secret n8n-secret -n n8n -o yaml > n8n-secret-backup.yaml

# Store safely (encrypted storage, password manager, etc.)
```

---

## Security Best Practices

### 1. Enable Authentication

n8n mặc định không có authentication. Enable ngay:

Thêm vào `04-deployment.yaml`:

```yaml
env:
  - name: N8N_BASIC_AUTH_ACTIVE
    value: "true"
  - name: N8N_BASIC_AUTH_USER
    valueFrom:
      secretKeyRef:
        name: n8n-secret
        key: BASIC_AUTH_USER
  - name: N8N_BASIC_AUTH_PASSWORD
    valueFrom:
      secretKeyRef:
        name: n8n-secret
        key: BASIC_AUTH_PASSWORD
```

Update Secret:

```yaml
stringData:
  BASIC_AUTH_USER: "admin"
  BASIC_AUTH_PASSWORD: "StrongPassword123!"
```

### 2. Network Policies

Giới hạn traffic chỉ từ Traefik:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: n8n-netpol
  namespace: n8n
spec:
  podSelector:
    matchLabels:
      app: n8n
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: TCP
          port: 5678
```

### 3. Backup Strategy

**Backup Postgres:**

```bash
# Trên VM Postgres
pg_dump -U n8n_user n8n_db > n8n_backup_$(date +%Y%m%d).sql

# Restore
psql -U n8n_user n8n_db < n8n_backup_20260208.sql
```

**Backup Longhorn Volume:**

- Dùng Longhorn UI để tạo snapshot định kỳ
- Hoặc dùng Velero để backup toàn bộ cluster

---

## Tài Liệu Tham Khảo

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Docker Setup](https://docs.n8n.io/hosting/installation/docker/)
- [n8n Environment Variables](https://docs.n8n.io/hosting/configuration/environment-variables/)
- [Traefik IngressRoute](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/)
- [Longhorn Documentation](https://longhorn.io/docs/)

---

**Version:** 1.0  
**n8n Version:** latest  
**Last Updated:** 2026-02-08  
**Tested on:** K3s v1.28+, Longhorn v1.5+, Traefik v2.10+
