# K3s Local Access Setup

Hướng dẫn cấu hình kubectl trên máy local để quản lý K3s cluster.

## ✅ **ĐÃ SETUP XONG!**

Kubeconfig đã được export và cấu hình tại: `~/.kube/k3s-config`

## 🚀 **SỬ DỤNG:**

### **Mở terminal mới:**
```bash
# KUBECONFIG đã được set trong ~/.zshrc
kubectl get nodes
kubectl get pods -A
```

### **Aliases đã có:**
```bash
k get nodes          # kubectl get nodes
kgp                  # kubectl get pods
kgn                  # kubectl get nodes
kgs                  # kubectl get svc
```

---

## 📝 **MANUAL SETUP (Nếu cần setup lại):**

### **Bước 1: Export kubeconfig từ K3s**
```bash
mkdir -p ~/.kube
scp tantai@172.16.21.11:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-config
```

### **Bước 2: Thay đổi server URL sang VIP**
```bash
sed -i '' 's/127.0.0.1/172.16.21.100/g' ~/.kube/k3s-config
```

### **Bước 3: Set KUBECONFIG**
```bash
export KUBECONFIG=~/.kube/k3s-config
```

### **Bước 4: Thêm vào ~/.zshrc (permanent)**
```bash
echo 'export KUBECONFIG=~/.kube/k3s-config' >> ~/.zshrc
source ~/.zshrc
```

---

## 🔄 **UPDATE KUBECONFIG (Khi cluster thay đổi):**

```bash
scp tantai@172.16.21.11:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-config
sed -i '' 's/127.0.0.1/172.16.21.100/g' ~/.kube/k3s-config
```

---

## 🎯 **CLUSTER INFO:**

- **VIP**: 172.16.21.100:6443
- **Nodes**: 
  - k3s-01: 172.16.21.11
  - k3s-02: 172.16.21.12
  - k3s-03: 172.16.21.13
