# Rancher Management Platform - Hướng Dẫn Truy Cập

## 📋 Tổng Quan

Rancher là nền tảng quản lý Kubernetes cluster, cung cấp giao diện web để quản lý workloads, services, và resources.

**Thông tin cluster:**
- K3s Version: v1.30.14+k3s2
- Rancher Version: 2.9.3
- Replicas: 1 (single instance cho homelab)
- Namespace: `cattle-system`
- Ingress Controller: Traefik (DaemonSet với hostPort 80/443)

---

## 🌐 Truy Cập Rancher Web UI

Rancher được expose qua **Ingress** với domain:

```
https://rancher.tantai.dev
```

### Kiến Trúc

```
Internet/LAN
    ↓
DNS: rancher.tantai.dev → 172.16.21.100 (VIP)
    ↓
Traefik Ingress Controller (hostPort 80/443 trên tất cả nodes)
    ↓
Rancher Service (ClusterIP - internal only)
    ↓
Rancher Pod
```

---

## 🔧 Setup DNS

### Option 1: Cloudflare DNS (Production - Khuyến nghị) ☁️

Config trên Cloudflare Dashboard:

```
Type: A Record
Name: rancher (hoặc rancher.tantai.dev)
Value: 172.16.21.100
TTL: Auto
Proxy Status: DNS only (tắt proxy)
```

**Lưu ý:** 
- Phải tắt Cloudflare Proxy (chọn "DNS only") vì IP private
- Nếu bật proxy, Cloudflare sẽ không route được tới IP private

**Wildcard (Optional - cho các services khác):**
```
Type: A Record
Name: * (wildcard)
Value: 172.16.21.100
TTL: Auto
Proxy Status: DNS only
```

Sau khi config, test:
```bash
# Check DNS resolution
nslookup rancher.tantai.dev

# Test access
curl -k https://rancher.tantai.dev
```

### Option 2: Local /etc/hosts (Testing) 💻

Nếu chưa config DNS hoặc test local:

```bash
# Thêm vào /etc/hosts
sudo sh -c 'echo "172.16.21.100 rancher.tantai.dev" >> /etc/hosts'

# Verify
cat /etc/hosts | grep rancher

# Test
curl -k https://rancher.tantai.dev
```

---

## 🔐 Đăng Nhập Lần Đầu

1. **Mở trình duyệt và truy cập:**
   ```
   https://172.16.21.11:30443
   ```

2. **Chấp nhận certificate warning:**
   - Click "Advanced" → "Proceed to 172.16.21.11 (unsafe)"
   - Đây là self-signed certificate, an toàn trong môi trường homelab

3. **Đăng nhập:**
   - Password: `21042004`
   - Click "Log in with Local User"

4. **Thiết lập lần đầu:**
   - Rancher sẽ yêu cầu set password mới (optional, có thể skip)
   - Configure Server URL: `https://172.16.21.11:30443`
   - Click "Save URL"

---

## 📊 Kiểm Tra Trạng Thái

### Kiểm tra pods Rancher

```bash
kubectl get pods -n cattle-system
```

Expected output:
```
NAME                       READY   STATUS    RESTARTS   AGE
rancher-8544f66bbc-xxxxx   1/1     Running   0          10m
```

### Kiểm tra service

```bash
kubectl get svc -n cattle-system
```

Expected output:
```
NAME      TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)                      AGE
rancher   NodePort   10.43.34.25   <none>        80:30080/TCP,443:30443/TCP   10m
```

### Kiểm tra ingress

```bash
kubectl get ingress -n cattle-system
```

### Xem logs

```bash
kubectl logs -n cattle-system -l app=rancher --tail=50
```

---

## 🔧 Quản Lý Cluster

### Import Cluster Hiện Tại

Sau khi đăng nhập, Rancher sẽ tự động detect local cluster (K3s cluster đang chạy Rancher).

1. Vào **Cluster Management**
2. Cluster `local` sẽ hiển thị (đây là K3s cluster)
3. Click vào để xem chi tiết nodes, workloads, storage

### Các Tính Năng Chính

1. **Cluster Dashboard:**
   - Xem tổng quan resources (CPU, Memory, Pods)
   - Monitor cluster health

2. **Workload Management:**
   - Deploy applications
   - Manage deployments, statefulsets, daemonsets
   - Scale replicas

3. **Service Discovery:**
   - Manage services, ingresses
   - Configure load balancing

4. **Storage:**
   - Manage PVCs, PVs
   - Configure storage classes (Longhorn)

5. **Monitoring:**
   - Install Prometheus + Grafana
   - View metrics and alerts

---

## 🛠️ Troubleshooting

### Rancher pod không start

```bash
# Xem logs
kubectl logs -n cattle-system -l app=rancher

# Xem events
kubectl get events -n cattle-system --sort-by='.lastTimestamp'

# Restart pod
kubectl delete pod -n cattle-system -l app=rancher
```

### Không truy cập được Web UI

```bash
# Kiểm tra service
kubectl get svc -n cattle-system

# Kiểm tra firewall trên node
ssh tantai@172.16.21.11 "sudo ufw status"

# Test kết nối
curl -k https://172.16.21.11:30443
```

### Certificate issues

Rancher sử dụng self-signed certificate mặc định. Để sử dụng certificate thật:

1. Cài cert-manager (đã có)
2. Tạo ClusterIssuer (Let's Encrypt)
3. Update Rancher Helm values với `ingress.tls.source=letsEncrypt`

---

## 📝 Ghi Chú

- **Password mặc định:** `21042004`
- **Replicas:** 1 (đủ cho homelab, production nên dùng 3)
- **Backup:** Rancher data được lưu trong K3s datastore (PostgreSQL)
- **Updates:** Có thể update qua Helm upgrade

---

## 🔄 Các Lệnh Hữu Ích

```bash
# Xem version Rancher
kubectl get deployment rancher -n cattle-system -o jsonpath='{.spec.template.spec.containers[0].image}'

# Restart Rancher
kubectl rollout restart deployment rancher -n cattle-system

# Scale Rancher (nếu cần)
kubectl scale deployment rancher -n cattle-system --replicas=1

# Uninstall Rancher (nếu cần)
helm uninstall rancher -n cattle-system

# Reinstall Rancher
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/setup-rancher.yml
```

---

**Cập nhật:** 2026-02-08
