# Hướng dẫn sử dụng Longhorn Distributed Storage

## 1. Giới thiệu
Longhorn là giải pháp lưu trữ phân tán (Distributed Block Storage) cho Kubernetes. Nó giả lập một "ổ cứng mạng" khổng lồ từ các ổ cứng rời rạc của từng node K3s.

### Tại sao cần Longhorn?
- **High Availability:** Dữ liệu tự động được sao chép (Replication) ra nhiều node (mặc định là 3 bản). Nếu 1 node chết, dữ liệu vẫn còn ở 2 node kia.
- **Tính di động:** Pod có thể di chuyển (reschedule) sang node khác thoải mái mà vẫn "nhìn thấy" dữ liệu cũ.
- **Backup & Snapshot:** Hỗ trợ backup dữ liệu lên S3 (MinIO, AWS S3) dễ dàng qua giao diện UI.

---

## 2. Các khái niệm cốt lõi

### StorageClass
Longhorn đã tạo sẵn một StorageClass mặc định tên là `longhorn`.
Khi deploy ứng dụng, bạn chỉ cần chỉ định `storageClassName: longhorn` (hoặc để trống nếu nó là default class).

### PVC (Persistent Volume Claim)
Là "phiếu yêu cầu" cấp phát dung lượng. Ví dụ: "Tôi cần 10GB ổ cứng". Kubernetes sẽ đưa phiếu này cho Longhorn, và Longhorn sẽ cắt 10GB để đưa cho Pod.

---

## 3. Ví dụ triển khai thực tế (MySQL)

Dưới đây là ví dụ triển khai một Database MySQL sử dụng Longhorn để lưu dữ liệu bền vững.

### Bước 1: Tạo file `mysql-longhorn.yaml`

```yaml
# 1. Yêu cầu cấp phát đĩa (PVC)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn  # Chỉ định dùng Longhorn
  resources:
    requests:
      storage: 5Gi  # Yêu cầu 5GB

---
# 2. Deploy MySQL Pod
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  selector:
    matchLabels:
      app: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - image: mysql:5.7
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: password
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql  # Mount ổ đĩa vào thư mục data của MySQL
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: mysql-pvc  # Link với PVC ở trên
```

### Bước 2: Apply vào Cluster

```bash
kubectl apply -f mysql-longhorn.yaml
```

### Bước 3: Kiểm tra trên Longhorn UI
1. Truy cập: [http://longhorn.tantai.dev](http://longhorn.tantai.dev)
2. Vào mục **Volume**: Bạn sẽ thấy một Volume mới (khoảng 5GB) đang ở trạng thái `Healthy`.
3. Nhìn cột **Replicas**: Sẽ thấy số `3` (tức là dữ liệu MySQL đang nằm trên cả 3 máy k3s-01, 02, 03).

---

## 4. Quản lý & Backup (Trên UI)

### Snapshot (Chụp nhanh)
- Vào Web UI -> Volume -> Chọn Volume của MySQL.
- Bấm **Take Snapshot**.
- Giúp bạn lưu lại trạng thái dữ liệu tại thời điểm đó. Nếu lỡ tay xóa nhầm data trong DB, có thể **Revert** lại snapshot này ngay lập tức.

### Backup (Lưu ra ngoài)
- Để đảm bảo an toàn tuyệt đối (ví dụ cháy cả cụm máy chủ), bạn nên config Backup Target trỏ về **MinIO** hoặc **AWS S3**.
- Vào Setting -> General -> Backup Target.
- Điền: `s3://backup-bucket@us-east-1/`

---

## 5. Lưu ý quan trọng
- **Đừng lưu dữ liệu quan trọng vào Local Path (`hostPath`)** nữa. Hãy luôn dùng PVC với Longhorn.
- **Replica Count:** Mặc định là 3. Với các dữ liệu ít quan trọng (như Cache), bạn có thể giảm xuống 1 hoặc 2 trong phần StorageClass config để tiết kiệm ổ cứng.
