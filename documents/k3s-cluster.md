# K3s HA Cluster Setup

> Kubernetes cluster với External PostgreSQL + Kube-VIP + Rancher

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Kiến trúc

```
┌─────────────────────────────────────────────────────────────────┐
│                    K3s HA CLUSTER                               │
│                                                                 │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                          │
│  │ k3s-01  │  │ k3s-02  │  │ k3s-03  │  ← 3 Converged Nodes     │
│  │ Server  │  │ Server  │  │ Server  │    (Prod-Network)        │
│  │ 4vCPU   │  │ 4vCPU   │  │ 4vCPU   │                          │
│  │ 6GB RAM │  │ 6GB RAM │  │ 6GB RAM │                          │
│  └────┬────┘  └────┬────┘  └────┬────┘                          │
│       │            │            │                               │
│       └────────────┼────────────┘                               │
│                    │                                            │
│              ┌─────┴─────┐                                      │
│              │ Kube-VIP  │  VIP: 172.16.21.100                  │
│              └─────┬─────┘                                      │
│                    │                                            │
│  ┌─────────────────┼─────────────────┐                          │
│  │                 │                 │                          │
│  ▼                 ▼                 ▼                          │
│  Postgres VM       MinIO VM          API Gateway                │
│  (DB State)        (S3 Backup)       (Reverse Proxy)            │
└─────────────────────────────────────────────────────────────────┘
```

### Điểm nổi bật

| Pattern                | Mô tả                                                   |
| ---------------------- | ------------------------------------------------------- |
| **External Datastore** | Dùng PostgreSQL thay vì etcd → giảm CPU/RAM cho nodes   |
| **Kube-VIP**           | Virtual IP cho API Server, không cần HAProxy            |
| **Converged Nodes**    | 3 node vừa Master vừa Worker → tiết kiệm tài nguyên     |
| **Stateless Nodes**    | Node chết? Xóa và join lại, data an toàn trong Postgres |

---

### Chi tiết kỹ thuật

#### 1. Kube-VIP: Software Load Balancer cho Homelab

File `kube-vip.yaml.j2` đóng vai trò **"Software Load Balancer"** cho cụm K3s. Trong Cloud (AWS, GCP), bạn có sẵn Load Balancer. Nhưng ở Homelab, file này tạo ra **Virtual IP (VIP)** để đạt chuẩn High Availability.

**Vấn đề:** Mỗi node có IP riêng. Nếu kubectl config trỏ vào 1 node cố định và node đó chết?

```
❌ Không có VIP:
┌─────────────────────────────────────────────────────────┐
│  kubeconfig: server: https://172.16.21.11:6443          │
│                                                         │
│  k3s-01 (172.16.21.11) ← kubectl trỏ vào đây            │
│  k3s-02 (172.16.21.12)                                  │
│  k3s-03 (172.16.21.13)                                  │
│                                                         │
│  Nếu k3s-01 chết → kubectl lỗi "Connection Refused"     │
│  Phải sửa config bằng tay → Downtime                    │
└─────────────────────────────────────────────────────────┘

✅ Có VIP (Floating IP):
┌─────────────────────────────────────────────────────────┐
│  kubeconfig: server: https://172.16.21.100:6443         │
│                                                         │
│  VIP 172.16.21.100 ← "Di chuyển" giữa các node          │
│       ↓                                                 │
│  k3s-01 (172.16.21.11) ← Đang giữ VIP (Leader)          │
│  k3s-02 (172.16.21.12)                                  │
│  k3s-03 (172.16.21.13)                                  │
│                                                         │
│  Nếu k3s-01 chết:                                       │
│  → Kube-VIP tự động chuyển VIP sang k3s-02              │
│  → kubectl vẫn connect bình thường (Zero downtime!)     │
└─────────────────────────────────────────────────────────┘
```

##### Phân tích file `kube-vip.yaml.j2`

**A. RBAC (Cấp quyền)**

```yaml
kind: ServiceAccount  # Tạo "nhân viên" tên kube-vip
kind: ClusterRole     # Định nghĩa quyền
kind: ClusterRoleBinding  # Gán quyền
```

Kube-VIP cần quyền đọc `Nodes`, `Services`, `Leases` để biết node nào đang sống và bầu chọn Leader.

**B. DaemonSet với hostNetwork**

```yaml
kind: DaemonSet
hostNetwork: true # ← Quan trọng nhất!
```

- **DaemonSet**: Chạy trên **tất cả Master nodes**
- **hostNetwork: true**: Cho phép Pod **can thiệp trực tiếp vào card mạng vật lý** để gán IP ảo. Không có dòng này, VIP không hoạt động!

**C. Environment Variables (Bộ não)**

```yaml
env:
  - name: vip_arp
    value: "true" # Layer 2 ARP mode - "hét" vào LAN

  - name: vip_interface
    value: "ens192" # Card mạng để gắn VIP

  - name: vip_address
    value: "172.16.21.100" # IP ảo

  - name: cp_enable
    value: "true" # Control Plane mode (port 6443)

  - name: vip_leaderelection
    value: "true" # Chỉ 1 node giữ VIP tại 1 thời điểm
```

##### Kịch bản Failover

```
1. BÌNH THƯỜNG:
   ┌──────────────────────────────────────────────────────┐
   │  Master 1 được bầu làm Leader                       │
   │  Master 1 nắm giữ VIP 172.16.21.100                 │
   │  Mọi request tới .100 → Master 1                    │
   └──────────────────────────────────────────────────────┘

2. SỰ CỐ:
   ┌──────────────────────────────────────────────────────┐
   │  Master 1 bị tắt nguồn / VM treo                    │
   │  Kube-VIP trên Master 2 & 3 thấy mất tín hiệu       │
   └──────────────────────────────────────────────────────┘

3. TỰ HỒI PHỤC (1-3 giây):
   ┌──────────────────────────────────────────────────────┐
   │  Master 2 tuyên bố: "Tao là Leader mới!"            │
   │  Master 2 gửi ARP ra mạng LAN chiếm IP .100         │
   │  → Cluster chỉ khựng 1-3 giây                       │
   │  → Truy cập bình thường qua IP cũ!                  │
   └──────────────────────────────────────────────────────┘
```

##### So sánh: VIP vs 3 IPs riêng

| Tiêu chí           | 3 IPs riêng                         | VIP (Kube-VIP)                  |
| ------------------ | ----------------------------------- | ------------------------------- |
| **Truy cập API**   | Trỏ từng IP, node chết → sửa config | 1 IP duy nhất, tự động failover |
| **Load Balancing** | DNS Round Robin (cache, chậm)       | ARP (tức thời, 1-3s)            |
| **Node chết**      | Admin phải sửa config               | Admin không làm gì cả           |
| **CI/CD tools**    | Bị lỗi khi node chết                | Không bị ảnh hưởng              |
| **Ingress/Web**    | Timeout do DNS cache                | Chuyển đổi trong giây           |

---

#### 2. External Datastore: Tại sao dùng PostgreSQL?

**So sánh:**

|                       | Embedded etcd            | External PostgreSQL        |
| --------------------- | ------------------------ | -------------------------- |
| **CPU/RAM trên node** | Cao (etcd consensus)     | Thấp (chỉ K3s agent)       |
| **Backup**            | Phức tạp (etcd snapshot) | Đơn giản (pg_dump)         |
| **Node chết**         | Phải recover etcd member | Xóa + join lại (stateless) |
| **Scale**             | Thêm node phức tạp       | Thêm node = 1 lệnh         |

**Connection string:**

```
postgres://k3s_prod:password@172.16.19.10:5432/k3s
         │         │         │              │
         │         │         │              └── Database name
         │         │         └── Postgres VM IP
         │         └── Password (từ Vault)
         └── Username (production tier)
```

**Lợi ích:**

- **Stateless nodes**: State lưu trong Postgres, không trên node
- **Dễ backup**: `pg_dump k3s > backup.sql`
- **Tái sử dụng**: Postgres VM đã có, không cần setup mới

---

#### 3. K3s Server Arguments

File `group_vars/k3s_servers.yml`:

```yaml
extra_server_args:
  - "--disable traefik" # ① Tắt Traefik mặc định
  - "--disable servicelb" # ② Tắt Klipper LoadBalancer
  - "--tls-san {{ vip_address }}" # ③ Cho phép VIP trong cert
```

| Argument              | Tại sao?                                                  |
| --------------------- | --------------------------------------------------------- |
| `--disable traefik`   | Dùng API Gateway VM riêng (có sẵn)                        |
| `--disable servicelb` | Dùng Kube-VIP thay vì Klipper LB                          |
| `--tls-san`           | Thêm VIP vào TLS certificate để kubectl qua VIP hoạt động |

---

#### 4. Converged Architecture

3 node chạy cả **Master** (control plane) lẫn **Worker** (workload):

```
┌─────────────────────────────────────────────────────────┐
│                    k3s-01                               │
│                                                         │
│  Control Plane:          Worker:                        │
│  ├── kube-apiserver      ├── kubelet                    │
│  ├── kube-scheduler      ├── containerd                 │
│  ├── kube-controller     └── Pods (Rancher, apps...)    │
│  └── Kube-VIP                                           │
└─────────────────────────────────────────────────────────┘
```

**Tại sao chọn converged?**

- Homelab có giới hạn tài nguyên
- 3 node riêng cho control plane = lãng phí
- Rancher + Longhorn có toleration chạy được trên master

---

### Triển khai

#### Bước 1: Tạo VMs với Terraform

```bash
# Apply từ Admin VM (tạo 3 K3s VMs + 50GB data disk)
./scripts/remote-apply.sh 192.168.1.100 tantai

# Lấy IPs
terraform output k3s_ips
```

#### Bước 2: Fix trùng IP (nếu VMs có cùng DHCP IP)

Truy cập từng VM qua **ESXi Console** và gán static IP tạm:

```bash
# k3s-01
sudo ip addr add 172.16.21.11/24 dev ens36
# k3s-02
sudo ip addr add 172.16.21.12/24 dev ens36
# k3s-03
sudo ip addr add 172.16.21.13/24 dev ens36
```

#### Bước 3: Update Inventory

Sửa `ansible/inventory/hosts.yml`:

```yaml
k3s_servers:
  hosts:
    k3s-01:
      ansible_host: 172.16.21.11
      static_ip: "172.16.21.11/24"
      gateway: "172.16.21.1"
      data_disk_device: "/dev/sdb"
      data_mount_point: "/mnt/longhorn"
    k3s-02:
      ansible_host: 172.16.21.12
      static_ip: "172.16.21.12/24"
      gateway: "172.16.21.1"
      data_disk_device: "/dev/sdb"
      data_mount_point: "/mnt/longhorn"
    k3s-03:
      ansible_host: 172.16.21.13
      static_ip: "172.16.21.13/24"
      gateway: "172.16.21.1"
      data_disk_device: "/dev/sdb"
      data_mount_point: "/mnt/longhorn"
  vars:
    ansible_user: tantai
    vm_hostname: "{{ inventory_hostname }}"
```

#### Bước 4: Setup VMs cơ bản

```bash
cd ansible
ansible-playbook playbooks/setup-vm.yml -l k3s_servers
```

#### Bước 5: Tạo K3s Database

```bash
ansible-playbook playbooks/postgres-add-database.yml \
  -e "db_name=k3s" \
  -e "master_pwd=xxx" \
  -e "prod_pwd=xxx" \
  -e "dev_pwd=xxx" \
  -e "readonly_pwd=xxx"
```

#### Bước 6: Thêm Vault Secrets

Sửa `group_vars/all/vault.yml`:

```yaml
vault_k3s_token: "your-secret-token"
vault_k3s_db_password: "xxx" # = prod_pwd ở bước 5
```

#### Bước 7: Deploy K3s Cluster

```bash
ansible-playbook playbooks/setup-k3s-cluster.yml
```

#### Bước 8: Install Rancher

```bash
ansible-playbook playbooks/setup-rancher.yml
```

### Verify

```bash
# SSH vào k3s-01
ssh tantai@172.16.21.x

# Check nodes
kubectl get nodes

# Check VIP
ping 172.16.21.100

# Check Rancher
curl -k https://rancher.tantai.dev
```

### Sử dụng

| Service | URL                                 | Mô tả              |
| ------- | ----------------------------------- | ------------------ |
| K3s API | https://172.16.21.100:6443          | Kubernetes API     |
| Rancher | https://rancher.tantai.dev          | Cluster Management |
| kubectl | Copy từ `/etc/rancher/k3s/k3s.yaml` | Local access       |

#### Cấu hình kubectl trên máy local

Để sử dụng `kubectl` từ máy local (laptop/desktop) để điều khiển cụm K3s:

````bash
# Dùng Ansible playbook (tự động lấy thông tin từ inventory)
cd ansible
ansible-playbook playbooks/export-kubeconfig.yml

Playbook sẽ tự động:

- Lấy kubeconfig từ node K3s đầu tiên trong inventory
- Thay server URL thành VIP (`172.16.21.100:6443`)
- Lưu vào `~/.kube/config` trên máy local
- Backup file config cũ (nếu có)

**Sau khi export, test kết nối:**

```bash
# Kiểm tra kết nối
kubectl get nodes

# Xem tất cả pods
kubectl get pods --all-namespaces

# Xem cluster info
kubectl cluster-info
````

**Lưu ý:**

- Script sẽ tự động backup file `~/.kube/config` cũ (nếu có)
- Kubeconfig sẽ được cấu hình để trỏ vào VIP (`172.16.21.100:6443`) thay vì IP node cụ thể
- Đảm bảo máy local có thể truy cập được VIP (cùng network hoặc VPN)
- File kubeconfig có quyền `600` (chỉ owner đọc/ghi)

**Nếu muốn dùng nhiều cluster cùng lúc:**

```bash
# Export vào file riêng
export KUBECONFIG=~/.kube/k3s-homelab.yaml
kubectl get nodes

# Hoặc merge vào config hiện tại
KUBECONFIG=~/.kube/config:~/.kube/k3s-homelab.yaml kubectl config view --flatten > ~/.kube/config
kubectl config use-context k3s-homelab
```

### TLS/SSL Certificate Management

#### Tổng quan

K3s cluster sử dụng **cert-manager** để tự động quản lý TLS certificates từ Let's Encrypt cho các Ingress resources.

**Flow hoạt động:**

```
1. Tạo ClusterIssuer (Let's Encrypt)
2. Apply Ingress với annotation cert-manager.io/cluster-issuer
3. cert-manager tự động tạo Certificate resource
4. Certificate tạo Challenge (HTTP-01 hoặc DNS-01)
5. Let's Encrypt validate domain
6. Certificate được ký và lưu vào Secret
7. Traefik sử dụng Secret để serve HTTPS
```

#### 1. cert-manager Installation

cert-manager được cài đặt tự động khi deploy Rancher:

**File:** `ansible/playbooks/setup-rancher.yml`

```yaml
# Install cert-manager via Helm
helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.17.0 \
--set installCRDs=true
```

**Kiểm tra:**

```bash
kubectl get pods -n cert-manager
# Should see:
# - cert-manager
# - cert-manager-cainjector
# - cert-manager-webhook
```

#### 2. ClusterIssuer Configuration

**File:** `documents/k3s-clusterissuer-example.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: nguyentantai.dev@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: traefik
```

**Apply:**

```bash
kubectl apply -f documents/k3s-clusterissuer-example.yaml
kubectl get clusterissuer letsencrypt-prod
```

**Giải thích:**

- **ACME server**: Let's Encrypt production endpoint
- **Email**: Dùng để nhận thông báo về certificate
- **HTTP-01 solver**: Validate domain qua HTTP challenge
- **Ingress class**: Traefik sẽ tạo challenge ingress

#### 3. Ingress với TLS

**Ví dụ Ingress:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portfolio
  namespace: pet-projects
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
spec:
  ingressClassName: traefik
  rules:
    - host: tantai.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: portfolio
                port:
                  number: 80
  tls:
    - hosts:
        - tantai.dev
      secretName: portfolio-tls
```

**Các thành phần:**

- **Annotation `cert-manager.io/cluster-issuer`**: Chỉ định ClusterIssuer để dùng
- **TLS section**: Khai báo domain và secret name cho certificate
- **Secret name**: cert-manager sẽ tạo secret này với certificate

#### 4. Certificate Lifecycle

**Kiểm tra Certificate:**

```bash
# Check certificate status
kubectl get certificate -n pet-projects

# Check certificate details
kubectl describe certificate portfolio-tls -n pet-projects

# Check secret (certificate data)
kubectl get secret portfolio-tls -n pet-projects -o yaml
```

**Certificate States:**

- **Issuing**: Đang được tạo
- **Ready**: Đã sẵn sàng, có thể dùng
- **Failed**: Lỗi trong quá trình tạo

#### 5. HTTP-01 Challenge Flow

**Quá trình validation:**

1. **cert-manager tạo Challenge:**

   ```bash
   kubectl get challenge -n pet-projects
   ```

2. **cert-manager tạo Challenge Ingress:**

   ```bash
   kubectl get ingress -n pet-projects | grep acme
   # Output: cm-acme-http-solver-xxxxx
   ```

3. **Let's Encrypt truy cập:**

   ```
   http://tantai.dev/.well-known/acme-challenge/<token>
   ```

4. **Traefik route đến challenge ingress:**

   - Challenge ingress expose ra K3s nodes (172.16.21.11:80, ...)
   - Let's Encrypt phải truy cập được từ internet

5. **Validation thành công:**
   - Certificate được ký
   - Lưu vào Secret
   - Traefik tự động reload và dùng certificate

#### 6. Yêu cầu DNS và Network Setup

**Quan trọng:** Domain phải trỏ về K3s cluster hoặc API Gateway để HTTP-01 challenge hoạt động.

**Flow với NoIP Dynamic DNS:**

```
Internet
  ↓
DNS (tantai.dev) → NoIP Dynamic DNS → External IP nhà (113.177.126.206)
  ↓
Router NAT/Port Forwarding (Port 80, 443)
  ↓
API Gateway (192.168.1.101:80/443)
  ↓
K3s Traefik (172.16.21.100:80)
  ↓
Challenge Ingress
  ↓
cert-manager pod
```

**Cấu hình cần thiết:**

1. **NoIP Dynamic DNS:**

   - Domain `tantai.dev` trỏ về NoIP hostname
   - NoIP client tự động update khi external IP thay đổi

2. **Router NAT/Port Forwarding:**

   ```
   External Port 80  → Internal IP 192.168.1.101:80  (API Gateway)
   External Port 443 → Internal IP 192.168.1.101:443 (API Gateway)
   ```

3. **API Gateway forward đến K3s:**
   - Đã cấu hình trong `dynamic_conf.yml.j2`
   - Route `k3s-services` forward đến `172.16.21.100:80`

**Nếu DNS/NAT chưa đúng:**

- Let's Encrypt không truy cập được challenge endpoint
- Lỗi: `wrong status code '404', expected '200'`
- Certificate không được ký

**Kiểm tra NAT/Port Forwarding:**

```bash
# Từ internet (hoặc dùng online tool)
curl http://<external-ip>:80/.well-known/acme-challenge/test
# Nếu response từ K3s → NAT OK
# Nếu timeout/refused → Check router port forwarding
```

#### 7. Troubleshooting TLS

**Certificate không được ký:**

```bash
# 1. Check certificate status
kubectl get certificate portfolio-tls -n pet-projects

# 2. Check challenge status
kubectl get challenge -n pet-projects
kubectl describe challenge <challenge-name> -n pet-projects

# 3. Check challenge ingress
kubectl get ingress -n pet-projects | grep acme
kubectl describe ingress cm-acme-http-solver-xxxxx -n pet-projects

# 4. Test challenge endpoint manually
curl http://tantai.dev/.well-known/acme-challenge/test
# Nếu 404 → DNS chưa trỏ đúng
# Nếu response từ K3s → OK

# 5. Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

**Lỗi thường gặp:**

| Lỗi                          | Nguyên nhân                    | Giải pháp                           |
| ---------------------------- | ------------------------------ | ----------------------------------- |
| `wrong status code '404'`    | DNS/NAT chưa đúng              | Check NoIP + Router port forwarding |
| `Connection refused`         | Challenge ingress không expose | Check Traefik và ingress            |
| `Certificate request failed` | Rate limit Let's Encrypt       | Đợi 1 giờ hoặc dùng staging         |
| `Challenge pending`          | DNS chưa propagate             | Đợi 5-10 phút                       |
| `Timeout`                    | Router không forward port 80   | Cấu hình NAT port forwarding        |

**Với NoIP Dynamic DNS:**

1. **Kiểm tra NoIP hostname:**

   ```bash
   nslookup tantai.dev
   # Phải trỏ về external IP nhà bạn
   ```

2. **Kiểm tra Router NAT:**

   - Vào router admin panel
   - Tìm "Port Forwarding" hoặc "Virtual Server"
   - Forward port 80 và 443 đến API Gateway (192.168.1.101)

3. **Test từ internet:**

   ```bash
   # Dùng online tool như https://www.yougetsignal.com/tools/open-ports/
   # Hoặc từ server khác
   curl http://<external-ip>:80
   # Phải response từ API Gateway/K3s
   ```

4. **Alternative: Dùng DNS-01 Challenge (nếu NoIP có API):**
   - Không cần port forwarding
   - cert-manager tự động tạo TXT record
   - Cần NoIP API credentials

**Force retry:**

```bash
# Delete challenge để retry
kubectl delete challenge <challenge-name> -n pet-projects

# Hoặc delete certificate để tạo lại
kubectl delete certificate portfolio-tls -n pet-projects
```

#### 8. Files liên quan

| File                                           | Mục đích                               |
| ---------------------------------------------- | -------------------------------------- |
| `documents/k3s-clusterissuer-example.yaml`     | ClusterIssuer config cho Let's Encrypt |
| `ansible/playbooks/setup-rancher.yml`          | Cài đặt cert-manager                   |
| `ansible/templates/k3s/traefik-config.yaml.j2` | Traefik config trong K3s               |
| `ansible/group_vars/k3s_servers.yml`           | K3s server args (TLS SAN)              |

#### 9. Best Practices

1. **Dùng staging trước khi production:**

   ```yaml
   server: https://acme-staging-v02.api.letsencrypt.org/directory
   ```

2. **Monitor certificate expiry:**

   ```bash
   kubectl get certificate -A
   # Certificates tự động renew trước khi expire
   ```

3. **Backup private keys:**

   ```bash
   kubectl get secret letsencrypt-prod -o yaml > backup.yaml
   ```

4. **Rate limiting:**
   - Let's Encrypt có rate limit: 50 certs/week/domain
   - Dùng staging để test trước

### Troubleshooting

#### K3s không start

```bash
# Check logs
journalctl -u k3s -f

# Check datastore connection
psql -h 172.16.19.10 -U k3s_prod -d k3s -c "SELECT 1"
```

#### Kube-VIP không hoạt động

```bash
# Check DaemonSet
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip

# Check VIP leader
kubectl get lease -n kube-system
```

#### Node không join cluster

```bash
# Check token
cat /var/lib/rancher/k3s/server/token

# Check network tới Postgres
nc -zv 172.16.19.10 5432
```

---

## English

### Architecture

K3s HA cluster with External PostgreSQL Datastore, Kube-VIP for Virtual IP, and Rancher for management.

### Highlights

| Pattern                | Description                                         |
| ---------------------- | --------------------------------------------------- |
| **External Datastore** | PostgreSQL instead of etcd → reduces node CPU/RAM   |
| **Kube-VIP**           | Virtual IP for API Server, no HAProxy needed        |
| **Converged Nodes**    | 3 nodes both Master + Worker → resource efficient   |
| **Stateless Nodes**    | Node dies? Delete and rejoin, data safe in Postgres |

### Deployment

```bash
# 1. Create VMs
terraform apply

# 2. Create K3s database
ansible-playbook playbooks/postgres-add-database.yml -e "db_name=k3s"

# 3. Setup K3s
ansible-playbook playbooks/setup-vm.yml -l k3s_servers
ansible-playbook playbooks/setup-k3s-cluster.yml

# 4. Install Rancher
ansible-playbook playbooks/setup-rancher.yml
```

### Access

| Service | URL                        |
| ------- | -------------------------- |
| K3s API | https://172.16.21.100:6443 |
| Rancher | https://rancher.tantai.dev |
