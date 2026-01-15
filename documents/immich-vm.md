# Immich Photo Management VM

Hệ thống quản lý ảnh/video self-hosted cho iPhone backup.

## Thông tin VM

- **Hostname:** immich
- **IP Address:** 172.16.21.30
- **vCPU:** 4 cores (cho CPU processing)
- **RAM:** 6GB (tối ưu cho CPU-only)
- **OS Disk:** 32GB (Ubuntu 24.04 LTS)
- **Data Disk:** 500GB (mounted tại `/mnt/media`)
- **Network:** prod_network (172.16.21.0/24)
- **GPU:** Không có (sử dụng CPU cho transcoding và ML)

## Dịch vụ

- **Immich Server:** Port 2283
- **PostgreSQL:** Internal (với pgvector extension)
- **Redis:** Internal
- **Machine Learning:** Internal (nhận diện khuôn mặt)

## Cấu trúc thư mục

```
/opt/immich/                    # Docker Compose stack
├── docker-compose.yml
└── .env

/mnt/media/immich/              # Data disk
├── library/                    # Photos & videos storage
└── postgres/                   # PostgreSQL data
```

## Triển khai

### 1. Tạo VM với Terraform

```bash
cd terraform
terraform apply
```

### 2. Cấu hình VM với Ansible

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/setup-immich.yml
```

### 3. Truy cập Web UI

Sau khi deploy xong, truy cập:

- **URL:** http://172.16.21.30:2283
- Tạo tài khoản Admin đầu tiên
- Cài đặt Immich Mobile App trên iPhone
- Cấu hình auto-backup

## Tối ưu hóa CPU-only

VM này được cấu hình để chạy hoàn toàn trên CPU (không có GPU).

### Cấu hình đã tối ưu

Các biến môi trường sau đã được thêm vào `.env`:

```bash
# FFmpeg transcoding (CPU-only)
IMMICH_MEDIA_FFMPEG_THREADS=2
IMMICH_MEDIA_FFMPEG_CRF=23
IMMICH_MEDIA_FFMPEG_PRESET=medium

# Machine Learning
IMMICH_MACHINE_LEARNING_WORKERS=1
IMMICH_MACHINE_LEARNING_WORKER_TIMEOUT=120
```

### Hiệu năng mong đợi

- **Ảnh HEIC:** Xử lý nhanh, không vấn đề gì
- **Video HEVC (iPhone):** Transcode sẽ chậm hơn, nhưng vẫn chạy được
  - Video ngắn (<1 phút): Smooth
  - Video dài (>5 phút): Có thể buffer khi xem lần đầu
- **Face Recognition:** Chạy được nhưng chậm hơn khi có GPU
  - ~100 ảnh: vài phút
  - ~1000 ảnh: 30-60 phút

### Tips tối ưu

1. **Giảm quality transcoding** nếu thấy quá chậm:

   - Vào Web UI → Settings → Video Settings
   - Giảm Target Resolution xuống 720p hoặc 480p

2. **Disable Face Recognition** nếu không cần:

   - Settings → Machine Learning Settings
   - Tắt "Face Detection"

3. **Upload ban đêm:** Import ảnh lúc ít dùng để tránh lag

### Backup

Script backup tự động sẽ được cung cấp sau khi hệ thống chạy ổn định. Script sẽ:

- Dump PostgreSQL database
- Rsync photos/videos ra USB
- Giữ metadata và cấu trúc thư mục

## Lưu ý quan trọng

### iPhone 11 Format

- **Ảnh:** HEIC (High Efficiency Image Format)
- **Video:** HEVC/H.265 (High Efficiency Video Coding)

Immich xử lý tốt cả hai format này. Khi xem trên web browser:

- Ảnh HEIC: Tự động convert để hiển thị
- Video HEVC: Transcode on-the-fly (cần CPU/GPU mạnh)

### Job Settings

Sau khi import ảnh lần đầu, vào **Administration → Settings → Job Settings** để điều chỉnh:

- **Concurrency:** Giảm xuống nếu VM bị overload
- **Face Detection:** Có thể tắt nếu không cần

## Troubleshooting

### Container không start

```bash
cd /opt/immich
docker-compose logs -f
```

### Database connection error

Kiểm tra PostgreSQL container:

```bash
docker logs immich_postgres
```

### Disk đầy

Kiểm tra dung lượng:

```bash
df -h /mnt/media
du -sh /mnt/media/immich/*
```

## WireGuard VPN Setup

### Tổng quan

WireGuard VPN được cài đặt trên cùng VM với Immich để cho phép truy cập từ xa an toàn. Cơ chế **On-Demand** giúp tối ưu pin trên iPhone 11.

### Cơ chế hoạt động

| Vị trí                           | Trạng thái VPN | Giải thích                                           |
| -------------------------------- | -------------- | ---------------------------------------------------- |
| **Ở nhà** (WiFi nhà)             | ❌ TẮT         | Kết nối trực tiếp qua LAN, tốc độ max, tiết kiệm pin |
| **Ra ngoài** (4G/WiFi công cộng) | ✅ BẬT         | Tự động kích hoạt VPN tunnel về nhà, bảo mật         |

**Điểm đặc biệt:**

- **Server (Homelab):** LUÔN MỞ 24/7 (container wg-easy chạy mãi)
- **iPhone Client:** THÔNG MINH - Tự động bật/tắt theo vị trí

### Đặc điểm WireGuard

- **Im lặng (Quiet):** Không gửi keep-alive packets → tiết kiệm pin
  - Khi không truyền dữ liệu, WireGuard ngủ đông hoàn toàn
  - OpenVPN phải ping server mỗi vài giây → tốn pin
- **Stateless:** Chuyển đổi WiFi ↔ 4G mượt mà, không đứt kết nối
- **Nhanh:** Handshake tức thì (mili-giây), không delay như OpenVPN

### Thông tin dịch vụ

- **WireGuard UI (wg-easy):** Port 51821 (Web UI)
- **WireGuard VPN:** Port 51820 (UDP)
- **Admin Password:** Lưu trong vault (`vault_wireguard_password`)
- **Peers:** Tối đa 10 devices
- **VPN Subnet:** 10.8.0.0/24
- **Allowed IPs:** 172.16.21.0/24 (homelab network)

### Cấu hình On-Demand cho iPhone

Sau khi tạo peer trên wg-easy Web UI:

1. **Truy cập wg-easy:**

   ```
   http://172.16.21.30:51821
   ```

2. **Tạo peer mới:**

   - Click "Add Client"
   - Name: `iPhone-11`
   - Quét QR Code bằng WireGuard app

3. **Bật On-Demand trên iPhone:**

   - Settings → VPN → WireGuard → (i)
   - Enable "On Demand"
   - Add Rule: **"Disconnect"** when on WiFi SSID: `Wifi_Nha_Minh` (thay bằng tên WiFi nhà bạn)
   - Add Rule: **"Connect"** when on Cellular/Other WiFi

4. **Quên nó đi:** VPN sẽ tự động bật/tắt

### Truy cập Immich qua VPN

Khi VPN bật (đang ở ngoài):

- **URL:** http://172.16.21.30:2283
- Hoặc setup DNS local: http://immich.home

### Tại sao setup này tối ưu cho iPhone 11?

iPhone 11 có pin yếu, nhưng với WireGuard On-Demand:

✅ **Ở nhà:** VPN tắt → Tốc độ max, không tốn pin  
✅ **Ra ngoài:** VPN bật → Bảo mật, nhưng chỉ tốn pin khi truyền dữ liệu  
✅ **Chuyển đổi:** Mượt mà, không đứt kết nối Zalo/Nhạc  
✅ **Set and Forget:** Cài một lần, dùng cả đời

## Next Steps

1. ✅ Deploy VM và services
2. ✅ Deploy WireGuard VPN
3. ⏳ Test upload ảnh/video từ iPhone
4. ⏳ Cấu hình WireGuard On-Demand trên iPhone
5. ⏳ Cấu hình backup script ra USB
6. ⏳ (Optional) Setup Traefik reverse proxy với HTTPS
7. ⏳ (Optional) Passthrough iGPU cho hardware acceleration
