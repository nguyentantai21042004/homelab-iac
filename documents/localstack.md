# Hướng dẫn Tích hợp LocalStack Pro

Tài liệu này chi tiết hóa kiến trúc và cấu hình để tích hợp LocalStack Pro vào hạ tầng homelab.

## 1. Tổng quan Kiến trúc

Để đảm bảo tính ổn định và hiệu năng, LocalStack Pro được triển khai trên một **VM Riêng biệt**, tách biệt khỏi cụm K3s. Điều này giúp tránh tranh chấp tài nguyên và cho phép tinh chỉnh kernel cụ thể theo yêu cầu của các thành phần trong LocalStack (Elasticsearch, v.v.).

- **Tên VM**: `localstack-pro`
- **Hệ điều hành**: Ubuntu (thông qua Cloud-Init)
- **Tài nguyên**:
  - vCPU: 4
  - RAM: 8GB
  - Disk: 100GB (mount tại `/mnt/data`)
- **Mạng**: Bridged vào `prod_network` (cùng dải mạng với K3s và Gateway).

## 2. Infrastructure as Code (IaC)

### Terraform

VM được khởi tạo bằng module `esxi-vm` tiêu chuẩn.

- **File**: `terraform/main.tf`
- **Module**: `module "localstack"`
- **Output**: `localstack_ip` (Sử dụng IP này cho DNS và Ansible inventory).

### Ansible

Cấu hình được tự động hóa thông qua `ansible/playbooks/setup-localstack.yml`.

#### Các Tối ưu Chính:

1.  **Tinh chỉnh Kernel (Kernel Tuning)**:
    - `fs.file-max`: 2097152 (Giới hạn file handle cao).
    - `vm.max_map_count`: 262144 (Bắt buộc cho Elasticsearch).
    - `net.core.somaxconn`: 65535 (Network throughput cao).
2.  **Chiến lược Lưu trữ**:
    - Ổ đĩa dữ liệu 100GB được format định dạng **XFS** và mount vào `/mnt/data`.
    - **Docker Root**: Cấu hình trỏ về `/mnt/data/docker` để tránh đầy ổ boot (OS disk).
    - **Persistence**: Dữ liệu LocalStack được lưu tại `/mnt/data/localstack_volume`.
3.  **Mạng (Networking)**:
    - Docker container chạy ở chế độ `network_mode: host`. Điều này loại bỏ overhead của Docker NAT và cải thiện hiệu năng đáng kể.
    - Service bind trực tiếp vào IP của VM trên port `4566`.

## 3. Sử dụng & Kết nối

### DNS & Routing

Traffic được định tuyến thông qua Traefik API Gateway.

- **Domain**: `aws.lab`, `s3.aws.lab`, `dynamodb.aws.lab`, `lambda.aws.lab`, `sqs.aws.lab`
- **Routing**: Traefik đón các domain này và forward về IP của LocalStack VM (port 4566).

### 🌐 Cấu hình DNS (Bắt buộc)

Để máy tính của bạn nhận diện được các domain `*.aws.lab`, bạn cần thêm vào file hosts.

**Thêm dòng sau (thay `192.168.1.21` bằng IP của API Gateway Traefik):**

```
192.168.1.21 aws.lab s3.aws.lab dynamodb.aws.lab lambda.aws.lab sqs.aws.lab cloudformation.aws.lab
```

> **Lưu ý:** File `/etc/hosts` không hỗ trợ wildcard (`*.aws.lab`). Nếu bạn cần thêm service AWS khác (ví dụ `kinesis.aws.lab`), hãy bổ sung vào dòng trên.

### Cách kết nối

1.  **AWS CLI**:
    ```bash
    aws --endpoint-url=http://s3.aws.lab:80 s3 ls
    ```
2.  **SDKs**: Cấu hình endpoint trỏ về `http://aws.lab` hoặc các subdomain dịch vụ cụ thể.
3.  **Dashboard Health**: Truy cập `https://aws.lab/_localstack/health` để kiểm tra trạng thái JSON.

### 🖥️ LocalStack UI (Web Dashboard)

LocalStack Pro đi kèm với **Web Dashboard** rất mạnh mẽ (quản lý S3, Lambda, DynamoDB trực quan). Do chúng ta chạy LocalStack trên VM (Remote), bạn cần cấu hình như sau:

1.  Truy cập: **[https://app.localstack.cloud](https://app.localstack.cloud)** (Đăng nhập bằng tài khoản Pro của bạn).
2.  Nhìn góc trên bên phải, phần **System Status** (hoặc Settings).
3.  Đổi **LocalStack Instance URL** từ `http://localhost:4566` thành:

    ```text
    https://aws.lab
    ```

    _(Lý do: Browser của bạn sẽ gọi đến `aws.lab` -> Traefik -> LocalStack VM)._

4.  Nếu thấy hiện **"Running"** màu xanh -> Kết nối thành công! Bạn có thể vào mục **Resources** để xem các bucket S3, Lambda function đang chạy.

### ⚠️ Cấu hình An toàn (Quan trọng)

Để tránh việc vô tình gọi nhầm lên AWS thật (và bị tính phí), bạn nên cấu hình **AWS Profile** riêng cho môi trường Lab.

**Bước 1: Tạo profile trong `~/.aws/config`**

```ini
[profile local]
region = us-east-1
output = json
endpoint_url = http://aws.lab
```

**Bước 2: Tạo credentials giả trong `~/.aws/credentials`**

```ini
[local]
aws_access_key_id = test
aws_secret_access_key = test
```

**Bước 3: Sử dụng**
Khi chạy lệnh, luôn thêm flag `--profile local`:

```bash
aws --profile local s3 ls
```

Hoặc set biến môi trường:

```bash
export AWS_PROFILE=local
aws s3 ls # Sẽ tự động trỏ về LocalStack
```

## 4. Bảo trì

- **Persistence**: Dữ liệu được lưu tại `/mnt/data/localstack_volume`. Hãy backup thư mục này để đảm bảo toàn vẹn dữ liệu.
- **Cập nhật**: Để update LocalStack, thay đổi image tag trong file `ansible/templates/localstack/docker-compose.yml.j2` và chạy lại playbook.
