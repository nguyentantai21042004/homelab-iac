# n8n Workflow Automation - K8s Deployment

## Tổng quan

n8n là workflow automation platform (tương tự Zapier, Make.com) được deploy trên K3s cluster với:

- **External PostgreSQL Database** (VM riêng: `172.16.19.10`)
- **Longhorn Storage** (3Gi, single replica)
- **LoadBalancer Service** (MetalLB)
- **HTTP Protocol** (không cần HTTPS cho internal use)

---

## Kiến trúc

```
┌─────────────────────────────────────────────────────┐
│              LoadBalancer (MetalLB)                 │
│              IP: 172.16.21.205:5678                 │
└────────────────────┬────────────────────────────────┘
                     │
              ┌──────▼──────┐
              │  n8n Pod    │
              │  (1 replica)│
              └──┬───────┬──┘
                 │       │
        ┌────────▼──┐ ┌──▼─────────────┐
        │ Longhorn  │ │ External       │
        │ PVC (3Gi) │ │ Postgres VM    │
        │ (Files)   │ │ (Database)     │
        └───────────┘ └────────────────┘
```

---

## Cấu trúc Files

```
n8n/
├── 00-namespace.yaml          # Namespace: automation
├── 01-storageclass.yaml       # Longhorn single replica StorageClass
├── 01-secret.yaml             # DB password + encryption key
├── 02-pvc.yaml                # Longhorn PVC 3Gi
├── 03-service.yaml            # LoadBalancer service
├── 04-deployment.yaml         # n8n deployment
├── deploy.sh                  # Deployment script
├── cleanup.sh                 # Cleanup script
└── README.md                  # This file
```

---

## Deployment

### Bước 1: Tạo Database (Ansible)

```bash
cd ansible
ansible-playbook playbooks/postgres-add-database.yml \
  -e "ansible_ssh_pass=21042004" \
  -e "db_name=n8n_db" \
  -e "master_pwd=21042004" \
  -e "dev_pwd=21042004" \
  -e "prod_pwd=21042004" \
  -e "readonly_pwd=21042004"
```

**Kết quả:**
- Database: `n8n_db`
- Users: `n8n_db_master`, `n8n_db_dev`, `n8n_db_prod`, `n8n_db_readonly`
- Multi-tenant isolation: ✅

### Bước 2: Deploy n8n

**Cách 1: Dùng script (Khuyến nghị)**

```bash
cd k8s-manifests/n8n
./deploy.sh
```

**Cách 2: Manual**

```bash
cd k8s-manifests/n8n

# Apply tất cả manifests
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-storageclass.yaml
kubectl apply -f 01-secret.yaml
kubectl apply -f 02-pvc.yaml
kubectl apply -f 03-service.yaml
kubectl apply -f 04-deployment.yaml
```

### Bước 3: Verify

```bash
# Check pods
kubectl get pods -n automation

# Check service
kubectl get svc -n automation

# Health check
curl http://172.16.21.205:5678/healthz
# Expected: {"status":"ok"}
```

---

## Cấu hình

### Database

- **Host**: `172.16.19.10:5432`
- **Database**: `n8n_db`
- **User**: `n8n_db_master` (có quyền migrations)
- **Password**: Lưu trong Secret `n8n-secret`

### Storage

- **StorageClass**: `longhorn-single-replica`
- **Size**: `3Gi`
- **Replicas**: `1` (để tiết kiệm storage)
- **Access Mode**: `ReadWriteOnce`

### Resources

```yaml
requests:
  cpu: 100m
  memory: 256Mi
limits:
  cpu: 1000m
  memory: 1Gi
```

### Environment Variables

```yaml
N8N_PORT: "5678"
N8N_PROTOCOL: "http"
N8N_SECURE_COOKIE: "false"  # Required for HTTP
NODE_ENV: "production"
GENERIC_TIMEZONE: "Asia/Ho_Chi_Minh"
```

---

## Truy cập

**LoadBalancer IP:**
```
http://172.16.21.205:5678
```

**Health Check:**
```bash
curl http://172.16.21.205:5678/healthz
```

**First Access:**
1. Mở browser: `http://172.16.21.205:5678`
2. Tạo owner account (email + password)
3. Bắt đầu tạo workflows

---

## Quản lý

### Xem Logs

```bash
kubectl logs -f deployment/n8n -n automation
```

### Restart Pod

```bash
kubectl rollout restart deployment/n8n -n automation
```

### Scale (nếu cần)

```bash
# Tăng replicas (cần Redis cho queue mode)
kubectl scale deployment/n8n -n automation --replicas=2
```

### Backup Encryption Key

**CRITICAL:** Encryption key mã hóa tất cả credentials trong n8n!

```bash
kubectl get secret n8n-secret -n automation -o yaml > n8n-secret-backup.yaml
```

Lưu file này ở nơi an toàn (password manager, encrypted storage).

---

## Troubleshooting

### Pod không start

```bash
# Check events
kubectl describe pod -l app=n8n -n automation

# Check PVC
kubectl get pvc -n automation
kubectl describe pvc n8n-pvc -n automation
```

### Database connection error

```bash
# Test connection từ pod
kubectl exec -it deployment/n8n -n automation -- sh
apk add postgresql-client
psql -h 172.16.19.10 -U n8n_db_master -d n8n_db
```

### Secure cookie error

Đảm bảo `N8N_SECURE_COOKIE: "false"` trong deployment (đã có sẵn).

### Insufficient storage

Nếu PVC không tạo được do thiếu storage:

1. Kiểm tra Longhorn storage:
```bash
kubectl get node.longhorn.io -n longhorn-system
```

2. Giảm size PVC hoặc xóa volumes không dùng:
```bash
kubectl get pvc -A
```

---

## Cleanup

**Dùng script:**

```bash
cd k8s-manifests/n8n
./cleanup.sh
```

**Manual:**

```bash
kubectl delete namespace automation
```

**Lưu ý:** Database trên Postgres VM không bị xóa.

### Xóa database (nếu cần)

```bash
ssh tantai@172.16.19.10
docker exec pg15_prod psql -U postgres -c "DROP DATABASE n8n_db;"
docker exec pg15_prod psql -U postgres -c "DROP USER n8n_db_master, n8n_db_dev, n8n_db_prod, n8n_db_readonly;"
```

---

## Tài liệu tham khảo

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Environment Variables](https://docs.n8n.io/hosting/configuration/environment-variables/)
- [Longhorn Documentation](https://longhorn.io/docs/)

---

**Version:** 1.0  
**n8n Version:** latest (2.6.4)  
**Last Updated:** 2026-02-08  
**Deployed on:** K3s v1.30.14+k3s2, Longhorn v1.5.3
