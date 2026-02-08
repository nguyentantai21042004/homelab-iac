# Hướng dẫn Triển khai Woodpecker CI

Tài liệu này chi tiết hóa kiến trúc và cấu hình để triển khai Woodpecker CI trong hạ tầng homelab.

## 1. Tổng quan Kiến trúc

Woodpecker CI được triển khai trên một **VM Riêng biệt** để cách ly việc build code ra khỏi các dịch vụ quan trọng khác (K3s, Database).

- **Tên VM**: `cicd`
- **Hệ điều hành**: Ubuntu (thông qua Cloud-Init)
- **Tài nguyên**:
  - vCPU: 4 (Build process ăn CPU nhiều)
  - RAM: 8GB (Dư dả cho Java/NodeJS builds)
  - Disk: 50GB SSD (I/O nhanh cho Docker cache)
- **Mạng**: Bridged vào `prod_network`.

### Kiến trúc Tối ưu

| Thành phần       | Mô tả                                                            |
| ---------------- | ---------------------------------------------------------------- |
| **Database**     | PostgreSQL (nhanh & ổn định hơn SQLite mặc định)                 |
| **Runtime**      | Docker Compose                                                   |
| **Build Engine** | DooD (Docker-outside-of-Docker) - Tận dụng Docker cache của Host |

## 2. Infrastructure as Code (IaC)

### Terraform

VM được khởi tạo bằng module `esxi-vm` tiêu chuẩn.

- **File**: `terraform/main.tf`
- **Module**: `module "cicd"`
- **Output**: `cicd_ip`

### Ansible Files

| File                                         | Mục đích                |
| -------------------------------------------- | ----------------------- |
| `group_vars/cicd_servers.yml`                | Config variables        |
| `templates/woodpecker/docker-compose.yml.j2` | Docker Compose template |
| `playbooks/setup-cicd.yml`                   | Setup playbook          |

## 3. Chuẩn bị trước khi Deploy

### 3.1 Tạo GitHub OAuth App

1. GitHub → Settings → Developer Settings → OAuth Apps → **New OAuth App**
2. Điền thông tin:
   - **Application name**: `Woodpecker CI Homelab`
   - **Homepage URL**: `https://ci.tantai.dev`
   - **Authorization callback URL**: `https://ci.tantai.dev/authorize`
3. Lưu lại **Client ID** và **Client Secret**.

### 3.2 Tạo Database trên PostgreSQL

```bash
ansible-playbook playbooks/postgres-add-database.yml \
  -e "db_name=woodpecker" \
  -e "master_pwd=<MASTER_PASSWORD>" \
  -e "prod_pwd=<PROD_PASSWORD>"
```

**Lưu ý:** Database sẽ được tạo với **multi-tenant isolation** (user của database khác không thể truy cập). Xem chi tiết tại [postgres-multi-tenant.md](postgres-multi-tenant.md).

### 3.3 Cập nhật Vault Secrets

Thêm vào `ansible/group_vars/all/vault.yml`:

```yaml
# Woodpecker CI secrets
vault_woodpecker_github_client: "Ov23liXXXXXXXXX" # GitHub OAuth Client ID
vault_woodpecker_github_secret: "your_client_secret" # GitHub OAuth Secret
vault_woodpecker_admin_user: "your_github_username" # GitHub username (admin)
vault_woodpecker_db_password: "your_db_password" # Same as step 3.2
vault_woodpecker_agent_secret: "random_32_char_string" # Generate with: openssl rand -hex 16
```

> **Tip**: Tạo agent secret bằng lệnh: `openssl rand -hex 16`

### 3.4 Cập nhật Inventory

Sau khi `terraform apply`, copy IP thực vào `ansible/inventory/hosts.yml`:

```yaml
cicd_servers:
  hosts:
    cicd:
      ansible_host: 172.16.21.XX # IP thực từ Terraform output
      ansible_user: your-user
```

## 4. Deploy

```bash
# 1. Tạo VM
cd terraform
terraform apply

# 2. Setup VM cơ bản (hostname, network)
cd ../ansible
ansible-playbook playbooks/setup-vm.yml -l cicd

# 3. Deploy Woodpecker
ansible-playbook playbooks/setup-cicd.yml
```

## 5. Sử dụng Woodpecker

### Truy cập Web UI

- **URL**: `https://ci.tantai.dev`
- Đăng nhập bằng GitHub
- Activate repository cần CI/CD

### Activate Repository

1. Login vào Dashboard
2. Click **"Add repository"** hoặc tìm repo trong list
3. Click **"Activate"** để enable CI/CD
4. Repo sẽ tự động nhận webhook từ GitHub

### Cấu hình Pipeline Cơ bản

Tạo file `.woodpecker.yml` trong root của repo:

```yaml
steps:
  - name: build
    image: node:20
    commands:
      - npm install
      - npm run build

  - name: test
    image: node:20
    commands:
      - npm test
```

### Filter theo Branch/Event

```yaml
# Chỉ chạy trên branch main
when:
  branch: main

steps:
  - name: build
    image: node:20
    commands:
      - npm run build
```

```yaml
# Chạy trên nhiều branches
when:
  branch: [main, develop, feature/*]

# Chạy theo event type
when:
  event: [push, pull_request, tag]

# Chạy chỉ khi có tag
when:
  event: tag
```

### Sử dụng Secrets

1. Vào **Repo Settings → Secrets** trên Dashboard
2. Add secret (VD: `docker_password`)
3. Sử dụng trong pipeline:

```yaml
steps:
  - name: docker-push
    image: docker
    environment:
      DOCKER_PASSWORD:
        from_secret: docker_password
    commands:
      - docker login -u myuser -p $DOCKER_PASSWORD
      - docker push myimage
```

### Push to Zot Registry (Private)

```yaml
steps:
  - name: docker
    image: woodpeckerci/plugin-docker-buildx
    settings:
      registry: 172.16.21.10:5000 # Zot Registry
      repo: 172.16.21.10:5000/my-app
      tags: [latest, "${CI_COMMIT_SHA:0:8}"]
      insecure: true
```

VM đã được cấu hình trust Zot registry (`insecure-registries` trong Docker daemon).

### Pipeline cho nhiều Stages

```yaml
steps:
  - name: install
    image: node:20
    commands:
      - npm ci

  - name: lint
    image: node:20
    commands:
      - npm run lint

  - name: test
    image: node:20
    commands:
      - npm test

  - name: build
    image: node:20
    commands:
      - npm run build
    when:
      branch: main

  - name: deploy
    image: alpine
    commands:
      - echo "Deploying to production..."
    when:
      event: push
      branch: main
```

> **Docs đầy đủ**: https://woodpecker-ci.org/docs/usage/intro

## 6. Chiến lược Tối ưu

### Docker Layer Caching

Nhờ DooD (mount `/var/run/docker.sock`), Agent dùng chung Docker Daemon với Host:

- Docker image layers được cache trên VM
- Build lần 2 trở đi sẽ skip các layer đã có
- **Kết quả**: Build time giảm từ 5 phút → 30 giây

### Garbage Collection

Container `docker-gc` tự động dọn rác lúc 3h sáng mỗi ngày:

- Xóa container rác
- Xóa dangling images
- Tránh đầy ổ cứng sau thời gian dài

### Version Pinning

Sử dụng specific version tag (`v3.12.0`) thay vì `:latest`:

- Tránh breaking changes khi có major version mới
- Kiểm soát được version đang chạy

### Update Woodpecker

```bash
# 1. Pull image mới
docker pull woodpeckerci/woodpecker-server:v3.12.0
docker pull woodpeckerci/woodpecker-agent:v3.12.0

# 2. Restart
cd /opt/woodpecker
docker-compose down && docker-compose up -d
```

### Troubleshooting

```bash
# Xem logs Server
docker logs woodpecker-server

# Xem logs Agent
docker logs woodpecker-agent

# Kiểm tra kết nối DB
docker exec woodpecker-server wget -qO- http://localhost:8000/healthz
```
