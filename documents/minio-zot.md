# MinIO + Zot Registry Setup

> Object Storage (MinIO) + OCI Registry (Zot) trên cùng VM với tách biệt Boot/Data disk

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Kiến trúc

```
┌─────────────────────────────────────────────────────────────────┐
│                    MINIO VM (172.16.20.10)                      │
│                    3 vCPU | 6GB RAM                             │
│                                                                 │
│  ┌─────────────────┐         ┌─────────────────────────────┐    │
│  │   Boot Disk     │         │      Data Disk (100GB)      │    │
│  │   /dev/sda      │         │      /dev/sdb               │    │
│  │                 │         │                             │    │
│  │  - Ubuntu OS    │         │  Mount: /mnt/minio_data     │    │
│  │  - Docker       │         │  Format: XFS                │    │
│  │  - System files │         │                             │    │
│  │                 │         │  └── minio-stack/           │    │
│  │                 │         │      ├── .env               │    │
│  │                 │         │      ├── docker-compose.yml │    │
│  │                 │         │      └── zot-config.json    │    │
│  └─────────────────┘         └─────────────────────────────┘    │
│                                        │                        │
│  ┌─────────────────────────────────────┴───────────────────┐    │
│  │                 Docker Containers                       │    │
│  │                                                         │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │    │
│  │  │    MinIO    │  │ Zot Registry│  │ MC (bucket  │      │    │
│  │  │   :9000     │  │    :5000    │  │  creator)   │      │    │
│  │  │   :9001     │  │             │  │             │      │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘      │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Dịch vụ

| Service       | Port | Mục đích                     |
| ------------- | ---- | ---------------------------- |
| MinIO API     | 9000 | S3-compatible API            |
| MinIO Console | 9001 | Web UI quản lý               |
| Zot Registry  | 5000 | OCI Registry (Docker images) |

### Triển khai

#### Bước 1: Tạo VM

```bash
# Thêm MinIO VM vào terraform
./scripts/remote-apply.sh 192.168.1.100 tantai

# Lấy IP
terraform output minio_ip
```

#### Bước 2: Update inventory

Sửa `ansible/inventory/hosts.yml`:

```yaml
minio:
  ansible_host: <IP từ output>
```

#### Bước 3: Chạy Ansible

```bash
cd ansible

# Setup cơ bản
ansible-playbook playbooks/setup-vm.yml -l minio

# Setup MinIO + Zot
ansible-playbook playbooks/setup-minio.yml
```

### Sử dụng

#### MinIO Console

- URL: `http://172.16.20.10:9001`
- Login: `admin` / `SuperSecretPassword123!`

#### Zot Registry

```bash
# Cấu hình Docker client (insecure registry)
echo '{"insecure-registries": ["172.16.20.10:5000"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

# Push image
docker tag alpine:latest 172.16.20.10:5000/my-alpine:v1
docker push 172.16.20.10:5000/my-alpine:v1

# Pull image
docker pull 172.16.20.10:5000/my-alpine:v1
```

#### MinIO S3 API

```bash
# Cài MinIO client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc

# Configure
./mc alias set myminio http://172.16.20.10:9000 admin SuperSecretPassword123!

# List buckets
./mc ls myminio

# Upload file
./mc cp file.txt myminio/zot-registry/
```

### Backup & Recovery

#### Snapshot Data Disk

1. Stop containers: `docker-compose down`
2. Snapshot `/dev/sdb` từ ESXi
3. Start containers: `docker-compose up -d`

#### Manual backup

```bash
# Backup MinIO data
tar -czf minio-backup.tar.gz /mnt/minio_data

# Restore
tar -xzf minio-backup.tar.gz -C /
```

---

## English

### Architecture

Object Storage (MinIO) + OCI Registry (Zot) on single VM with separate Boot/Data disks.

### Services

| Service       | Port | Purpose                        |
| ------------- | ---- | ------------------------------ |
| MinIO API     | 9000 | S3-compatible API              |
| MinIO Console | 9001 | Web management UI              |
| Zot Registry  | 5000 | OCI Registry for Docker images |

### Deployment

#### Step 1: Create VM

```bash
./scripts/remote-apply.sh 192.168.1.100 tantai
terraform output minio_ip
```

#### Step 2: Run Ansible

```bash
cd ansible
ansible-playbook playbooks/setup-vm.yml -l minio
ansible-playbook playbooks/setup-minio.yml
```

### Usage

#### Access MinIO Console

- URL: `http://172.16.20.10:9001`
- Login: `admin` / `SuperSecretPassword123!`

#### Use Zot Registry

```bash
# Configure Docker for insecure registry
echo '{"insecure-registries": ["172.16.20.10:5000"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

# Push/Pull images
docker tag alpine:latest 172.16.20.10:5000/my-alpine:v1
docker push 172.16.20.10:5000/my-alpine:v1
```
