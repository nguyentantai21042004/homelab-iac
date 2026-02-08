# Homelab Infrastructure - Tổng Hợp Deployment

## 📊 Tổng Quan Hệ Thống

Homelab infrastructure đã được deploy thành công với các thành phần sau:

### 1. PostgreSQL Database Server ✅
- **IP:** 172.16.19.10
- **Version:** PostgreSQL 15
- **Data Path:** /mnt/pg_data
- **Status:** Running
- **Databases:**
  - `postgres` (default)
  - `k3s` (K3s datastore)

### 2. Storage Server (MinIO + Zot) ✅
- **IP:** 172.16.21.10
- **MinIO Console:** http://172.16.21.10:9001
- **MinIO API:** http://172.16.21.10:9000
- **Zot Registry:** http://172.16.21.10:5000
- **Status:** Running

### 3. K3s Kubernetes Cluster ✅
- **VIP:** 172.16.21.100
- **Version:** v1.30.14+k3s2
- **Nodes:**
  - k3s-01: 172.16.21.11 (Control Plane)
  - k3s-02: 172.16.21.12 (Control Plane)
  - k3s-03: 172.16.21.13 (Control Plane)
- **Storage:** Longhorn v1.5.3
- **Datastore:** External PostgreSQL
- **Status:** Running

### 4. Rancher Management Platform ✅
- **URL:** https://172.16.21.11:30443
- **Version:** 2.9.3
- **Replicas:** 1
- **Status:** Running

---

## 🔐 Credentials Chung

**Tất cả services sử dụng:**
- Username: `tantai`
- Password: `21042004`

Chi tiết đầy đủ xem file: `CREDENTIALS.md`

---

## 📁 Cấu Trúc Thư Mục

```
homelab-iac/
├── terraform/              # Terraform configs cho VMs
├── ansible/
│   ├── inventory/
│   │   └── hosts.yml      # Inventory tất cả VMs
│   ├── playbooks/         # Ansible playbooks
│   │   ├── setup-postgres.yml
│   │   ├── setup-storage.yml
│   │   ├── setup-k3s-cluster.yml
│   │   ├── setup-longhorn.yml
│   │   └── setup-rancher.yml
│   ├── roles/             # Ansible roles
│   └── group_vars/        # Variables và vault
├── usages/                # Hướng dẫn sử dụng
│   ├── K3S_LOCAL_ACCESS.md
│   ├── RANCHER_ACCESS.md
│   └── DEPLOYMENT_SUMMARY.md (file này)
├── Makefile              # Quick commands
└── CREDENTIALS.md        # Thông tin đăng nhập (gitignored)
```

---

## 🚀 Quy Trình Deploy

### Bước 1: Tạo VM với Terraform

```bash
# PostgreSQL
make apply-postgres

# Storage
make apply-storage

# K3s Cluster (3 nodes)
make apply-k3s
```

### Bước 2: Setup với Ansible

```bash
# Export password để tránh nhập nhiều lần
export ANSIBLE_SSH_PASSWORD="21042004"

# PostgreSQL
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/setup-postgres.yml

# Storage (MinIO + Zot)
ansible-playbook -i inventory/hosts.yml playbooks/setup-storage.yml

# K3s Database Setup
ansible-playbook -i inventory/hosts.yml playbooks/postgres-setup-k3s-db.yml

# K3s Cluster
ansible-playbook -i inventory/hosts.yml playbooks/setup-k3s-cluster.yml

# Longhorn Storage
ansible-playbook -i inventory/hosts.yml playbooks/setup-longhorn.yml

# Rancher
ansible-playbook -i inventory/hosts.yml playbooks/setup-rancher.yml
```

### Bước 3: Cấu Hình Local Access

```bash
# Export kubeconfig
ansible-playbook -i inventory/hosts.yml playbooks/export-kubeconfig.yml

# Thêm vào ~/.zshrc
export KUBECONFIG=~/.kube/k3s-config

# Reload shell
source ~/.zshrc

# Test
kubectl get nodes
```

---

## 🔍 Kiểm Tra Trạng Thái

### PostgreSQL

```bash
ssh tantai@172.16.19.10 "docker ps"
psql -h 172.16.19.10 -U tantai -d postgres -c "SELECT version();"
```

### Storage

```bash
# MinIO
curl http://172.16.21.10:9000/minio/health/live

# Zot
curl http://172.16.21.10:5000/v2/_catalog
```

### K3s Cluster

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pv,pvc -A
```

### Rancher

```bash
kubectl get pods -n cattle-system
curl -k -I https://172.16.21.11:30443
```

---

## 📚 Tài Liệu Tham Khảo

- **K3s Local Access:** `usages/K3S_LOCAL_ACCESS.md`
- **Rancher Access:** `usages/RANCHER_ACCESS.md`
- **Credentials:** `CREDENTIALS.md`
- **Ansible Inventory:** `ansible/inventory/hosts.yml`

---

## 🛠️ Troubleshooting

### VM không SSH được

```bash
# Kiểm tra IP
ssh tantai@<IP>

# Copy SSH key
sshpass -p "21042004" ssh-copy-id tantai@<IP>

# Fix network (nếu cần)
ansible-playbook -i inventory/hosts.yml playbooks/fix-network.yml -l <hostname>
```

### K3s node không join

```bash
# Kiểm tra logs trên node
ssh tantai@<node-ip> "sudo journalctl -u k3s -f"

# Kiểm tra PostgreSQL connection
ssh tantai@<node-ip> "curl -v telnet://172.16.19.10:5432"

# Reset và join lại
ssh tantai@<node-ip> "sudo /usr/local/bin/k3s-uninstall.sh"
ansible-playbook -i inventory/hosts.yml playbooks/setup-k3s-cluster.yml -l <hostname>
```

### Rancher không truy cập được

```bash
# Kiểm tra pods
kubectl get pods -n cattle-system

# Kiểm tra service
kubectl get svc -n cattle-system

# Xem logs
kubectl logs -n cattle-system -l app=rancher

# Restart
kubectl rollout restart deployment rancher -n cattle-system
```

---

## 🎯 Next Steps

### 1. Deploy Applications

```bash
# Tạo namespace
kubectl create namespace myapp

# Deploy app
kubectl apply -f myapp.yaml -n myapp
```

### 2. Setup Monitoring

```bash
# Install Prometheus + Grafana qua Rancher UI
# Hoặc dùng Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### 3. Setup CI/CD

```bash
# Deploy Woodpecker CI
ansible-playbook -i inventory/hosts.yml playbooks/setup-cicd.yml
```

### 4. Setup API Gateway

```bash
# Deploy Traefik
ansible-playbook -i inventory/hosts.yml playbooks/setup-api-gateway.yml
```

---

## 📝 Ghi Chú Quan Trọng

1. **Backup:**
   - PostgreSQL data: `/mnt/pg_data`
   - Longhorn data: `/mnt/longhorn`
   - MinIO data: `/mnt/storage_data/minio`

2. **Security:**
   - Đổi password mặc định trong production
   - Enable firewall trên các VMs
   - Sử dụng SSH keys thay vì password

3. **Monitoring:**
   - Setup Prometheus/Grafana để monitor cluster
   - Enable Longhorn monitoring
   - Setup alerts cho critical services

4. **Updates:**
   - K3s: `ansible-playbook playbooks/update-k3s.yml`
   - Rancher: `helm upgrade rancher rancher-stable/rancher -n cattle-system`
   - Longhorn: Qua Rancher UI hoặc Helm

---

**Cập nhật:** 2026-02-08
**Status:** All services running ✅
