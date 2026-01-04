# Mutagen - File Synchronization Tool

## Mục lục

- [Giới thiệu](#giới-thiệu)
- [Cơ chế hoạt động](#cơ-chế-hoạt-động)
  - [1. Kiến trúc Agent-based](#1-kiến-trúc-agent-based)
  - [2. Theo dõi thay đổi thời gian thực](#2-theo-dõi-thay-đổi-thời-gian-thực)
  - [3. Thuật toán hợp nhất ba chiều](#3-thuật-toán-hợp-nhất-ba-chiều)
  - [4. Truyền dữ liệu vi phân](#4-truyền-dữ-liệu-vi-phân)
  - [5. Cập nhật nguyên tử](#5-cập-nhật-nguyên-tử)
- [So sánh với rsync](#so-sánh-với-rsync)
- [Áp dụng trong Homelab IaC](#áp-dụng-trong-homelab-iac)
  - [Workflow](#workflow)
  - [Giải thích các scripts](#giải-thích-các-scripts)
- [Cài đặt và sử dụng](#cài-đặt-và-sử-dụng)

---

## Giới thiệu

Mutagen là công cụ đồng bộ hóa file hiệu suất cao, được thiết kế cho quy trình phát triển phần mềm hiện đại. Đặc biệt phù hợp khi làm việc với Docker hoặc Server từ xa.

**Điểm mạnh:**

- Đồng bộ 2 chiều (bidirectional) real-time
- Không cần cài đặt phức tạp ở máy đích
- Xử lý xung đột thông minh
- Tối ưu băng thông (chỉ gửi phần thay đổi)

---

## Cơ chế hoạt động

### 1. Kiến trúc Agent-based

Mutagen sử dụng mô hình **Alpha** (máy gửi) và **Beta** (máy nhận):

```
┌─────────────┐         SSH/Docker         ┌─────────────┐
│   Alpha     │ ◄─────────────────────────►│    Beta     │
│  (Local)    │                            │  (Remote)   │
│             │    Tự động gửi Agent       │             │
│  Mutagen    │ ─────────────────────────► │   Agent     │
│  Daemon     │                            │  (tự chạy)  │
└─────────────┘                            └─────────────┘
```

- **Tự động tiêm Agent:** Khi khởi tạo session, Mutagen tự động nhận diện OS và CPU của máy đích, gửi binary agent nhỏ (viết bằng Go) qua SSH
- **Chạy độc lập:** Agent chạy trong bộ nhớ, thực hiện hashing và quét file trực tiếp trên máy đích → giảm tải băng thông

### 2. Theo dõi thay đổi thời gian thực

Thay vì quét toàn bộ ổ cứng liên tục (tốn CPU như rsync), Mutagen dùng API native:

| OS      | API                   |
| ------- | --------------------- |
| macOS   | FSEvents              |
| Linux   | inotify               |
| Windows | ReadDirectoryChangesW |

Nếu hệ thống không hỗ trợ watching, Mutagen chuyển sang polling được tối ưu hóa.

### 3. Thuật toán hợp nhất ba chiều

Đây là "bộ não" xử lý đồng bộ 2 chiều:

```
        Ancestor (snapshot cuối cùng đã thống nhất)
              │
    ┌─────────┴─────────┐
    ▼                   ▼
  Alpha              Beta
(thay đổi?)       (thay đổi?)
```

**Logic xử lý:**

- Alpha thay đổi, Beta giữ nguyên → Cập nhật Beta
- Beta thay đổi, Alpha giữ nguyên → Cập nhật Alpha
- Cả hai cùng thay đổi khác nhau → **Conflict** (không tự ghi đè)

### 4. Truyền dữ liệu vi phân

Khi file lớn (1GB) chỉ thay đổi vài byte:

```
File gốc: [████████████████████████████████] 1GB
Thay đổi: [████░░████████████████████████████]
                ↑ chỉ 1KB thay đổi

Mutagen chỉ gửi: [░░] 1KB (delta)
```

- Chia file thành chunks
- Tính hash từng chunk
- Chỉ truyền phần khác biệt (delta)

### 5. Cập nhật nguyên tử

Tránh file bị lỗi nếu mạng ngắt giữa chừng:

```
1. Tải vào Staging area (thư mục tạm)
2. Kiểm tra hash
3. rename() (atomic operation) → thay thế file cũ
```

File không bao giờ ở trạng thái "nửa cũ nửa mới".

---

## So sánh với rsync

| Đặc điểm            | rsync                 | Mutagen              |
| ------------------- | --------------------- | -------------------- |
| **Hướng đồng bộ**   | 1 chiều               | 2 chiều              |
| **Tốc độ phản ứng** | Chạy thủ công/định kỳ | Real-time            |
| **Xử lý xung đột**  | Ghi đè trực tiếp      | Phát hiện và báo cáo |
| **Setup**           | Cần cài ở cả 2 đầu    | Tự động inject agent |

---

## Áp dụng trong Homelab IaC

### Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  LOCAL (Kiro IDE)              ADMIN VM (trong ESXi)        │
│       │                              │                      │
│       │◄────── Mutagen Sync ────────►│                      │
│       │      (2-way real-time)       │                      │
│       │                              │                      │
│  - Edit code                    - terraform apply           │
│  - terraform plan               - ansible-playbook          │
│  - Git commit                   - Tạo VM nhanh (internal)   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Tại sao cần setup này?**

Provider `josenk/esxi` khi clone VM sẽ:

1. Export template từ ESXi về máy local
2. Upload lại lên ESXi

→ Chậm vì data đi qua mạng 2 lần.

Với Admin VM trong ESXi:

- Traffic chỉ trong internal network (10Gbps+)
- Clone VM nhanh hơn nhiều (1-2 phút thay vì 10+ phút)

### Giải thích các scripts

#### `scripts/sync-start.sh`

```bash
./scripts/sync-start.sh <admin-vm-ip> <user>
```

**Chức năng:** Khởi tạo sync session giữa local và Admin VM

**Cách hoạt động:**

```bash
mutagen sync create \
    .                                    # Alpha: thư mục hiện tại (local)
    user@admin-vm:/home/user/homelab-iac # Beta: thư mục trên Admin VM
    --name="homelab-iac"                 # Tên session
    --ignore=".terraform"                # Bỏ qua thư mục .terraform
    --ignore="*.tfstate"                 # Bỏ qua state files
    --ignore="tools/"                    # Bỏ qua tools (OVF Tool)
    --sync-mode="two-way-resolved"       # 2 chiều, tự resolve conflict
```

**Các file được ignore:**

- `.terraform/` - Provider cache, không cần sync
- `*.tfstate` - State file, mỗi máy có riêng
- `tools/` - OVF Tool binary, đã cài trên Admin VM

#### `scripts/sync-stop.sh`

```bash
./scripts/sync-stop.sh
```

**Chức năng:** Dừng sync session

#### `scripts/remote-apply.sh`

```bash
./scripts/remote-apply.sh <admin-vm-ip> <user>
```

**Chức năng:** SSH vào Admin VM và chạy `terraform apply`

**Flow:**

```
Local                          Admin VM
  │                               │
  │── SSH ───────────────────────►│
  │                               │── cd homelab-iac/terraform
  │                               │── terraform apply
  │◄── Output ────────────────────│
```

#### `scripts/remote-destroy.sh`

```bash
./scripts/remote-destroy.sh <admin-vm-ip> <user>
```

**Chức năng:** SSH vào Admin VM và chạy `terraform destroy`

---

## Cài đặt và sử dụng

### 1. Cài Mutagen (macOS)

```bash
brew install mutagen-io/mutagen/mutagen
```

### 2. Khởi động sync

```bash
# Thay IP và user thật
./scripts/sync-start.sh 192.168.1.100 tantai
```

### 3. Kiểm tra status

```bash
mutagen sync list
mutagen sync monitor  # Real-time monitor
```

### 4. Workflow hàng ngày

```bash
# 1. Edit code trên local (tự sync sang Admin VM)

# 2. Preview changes
terraform plan

# 3. Apply từ Admin VM (nhanh)
./scripts/remote-apply.sh 192.168.1.100 tantai

# 4. Hoặc destroy
./scripts/remote-destroy.sh 192.168.1.100 tantai
```

### 5. Dừng sync khi không cần

```bash
./scripts/sync-stop.sh
```

---

## Xử lý sự cố

### Conflict

Nếu edit cùng file ở cả 2 nơi:

```bash
mutagen sync list  # Xem có conflict không
mutagen sync reset homelab-iac  # Reset về trạng thái Alpha
```

### Sync chậm/không hoạt động

```bash
mutagen sync terminate homelab-iac
./scripts/sync-start.sh <ip> <user>
```

### Xem logs

```bash
mutagen daemon log
```
