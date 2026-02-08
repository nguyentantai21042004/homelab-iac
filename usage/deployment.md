# VM Deployment Workflow

Hướng dẫn chi tiết các bước deploy một VM từ Terraform đến Ansible configuration.

## Tổng quan

Workflow gồm 2 giai đoạn chính:
1. **Terraform**: Tạo VM infrastructure trên ESXi
2. **Ansible**: Cấu hình VM (network, packages, services)

---

## Bước 1: Terraform - Tạo VM

### 1.1. Chạy Terraform apply

```bash
make apply-postgres
```

Hoặc cho module khác:
```bash
make apply-<module-name>
```

### 1.2. Lấy IP của VM mới tạo

Terraform sẽ output IP động (DHCP) của VM:

```
Outputs:
postgres_ip = "172.16.19.116"
```

**Lưu ý:** IP này là IP động từ DHCP, sẽ được đổi sang static IP ở bước Ansible.

---

## Bước 2: Cập nhật Ansible Inventory

### 2.1. Mở file inventory

```bash
vim ansible/inventory/hosts.yml
```

### 2.2. Update `ansible_host` với IP từ Terraform

Tìm section của VM và update `ansible_host`:

```yaml
postgres_servers:
  hosts:
    postgres:
      ansible_host: 172.16.19.116  # ← Update IP này
      ansible_user: tantai
      vm_hostname: "postgres"
      static_ip: "172.16.19.10/24"  # ← IP tĩnh sẽ được set bởi Ansible
      gateway: "172.16.19.1"
      data_disk_device: "/dev/sdb"
      data_mount_point: "/mnt/pg_data"
```

---

## Bước 3: Setup SSH Key

### 3.1. Add host key vào known_hosts

```bash
ssh-keyscan -H <VM_IP> >> ~/.ssh/known_hosts
```

Ví dụ:
```bash
ssh-keyscan -H 172.16.19.116 >> ~/.ssh/known_hosts
```

### 3.2. Copy SSH key vào VM

```bash
ssh-copy-id tantai@<VM_IP>
```

Ví dụ:
```bash
ssh-copy-id tantai@172.16.19.116
```

**Lưu ý:** Cần nhập password của user `tantai` trên VM.

---

## Bước 4: Chạy Ansible Playbook

### 4.1. Chạy setup playbook

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/setup-<service>.yml
```

Ví dụ cho PostgreSQL:
```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/setup-postgres.yml
```

### 4.2. Playbook sẽ thực hiện

1. **Common role**: Set timezone, hostname, static IP
2. **Kernel tuning**: Optimize kernel parameters
3. **Docker**: Install Docker
4. **Data disk**: Format và mount disk bổ sung
5. **Service role**: Setup service cụ thể (PostgreSQL, MinIO, etc.)

### 4.3. VM sẽ đổi IP

Sau khi playbook chạy xong, VM sẽ chuyển từ IP động sang static IP đã định nghĩa trong inventory.

---

## Bước 5: Update Inventory lần cuối

### 5.1. Update `ansible_host` sang static IP

Mở lại `ansible/inventory/hosts.yml` và update:

```yaml
postgres_servers:
  hosts:
    postgres:
      ansible_host: 172.16.19.10  # ← Update sang static IP
      ansible_user: tantai
      vm_hostname: "postgres"
      static_ip: "172.16.19.10/24"
      gateway: "172.16.19.1"
```

### 5.2. Verify kết nối

```bash
ping 172.16.19.10
ssh tantai@172.16.19.10
```

---

## Checklist tổng hợp

- [ ] 1. Chạy `make apply-<module>` để tạo VM
- [ ] 2. Lấy IP từ terraform output
- [ ] 3. Update `ansible_host` trong `ansible/inventory/hosts.yml`
- [ ] 4. Chạy `ssh-keyscan -H <IP> >> ~/.ssh/known_hosts`
- [ ] 5. Chạy `ssh-copy-id tantai@<IP>`
- [ ] 6. Chạy `cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/setup-<service>.yml`
- [ ] 7. Update `ansible_host` sang static IP trong inventory
- [ ] 8. Verify: `ping <static_IP>` và `ssh tantai@<static_IP>`

---

## Troubleshooting

### VM không ping được sau khi Ansible chạy xong

**Nguyên nhân:** VM đã chuyển sang static IP nhưng bạn đang ping IP cũ.

**Giải pháp:** 
- Check console trên ESXi để xem IP hiện tại
- Hoặc ping static IP đã định nghĩa trong inventory

### Ansible timeout khi apply netplan

**Nguyên nhân:** Task `netplan apply` làm mất kết nối SSH tạm thời.

**Giải pháp:** 
- Đợi 1-2 phút để VM restart network
- Check IP mới từ ESXi console
- Update inventory và chạy lại playbook

### SSH key không hoạt động

**Nguyên nhân:** Ansible không tìm thấy SSH key.

**Giải pháp:**
- Check `ansible/ansible.cfg` có `private_key_file` đúng không
- Hoặc dùng `--ask-pass` khi chạy playbook

---

## Ví dụ hoàn chỉnh: Deploy PostgreSQL VM

```bash
# 1. Tạo VM
make apply-postgres
# Output: postgres_ip = "172.16.19.116"

# 2. Update inventory
vim ansible/inventory/hosts.yml
# Sửa ansible_host: 172.16.19.116

# 3. Setup SSH
ssh-keyscan -H 172.16.19.116 >> ~/.ssh/known_hosts
ssh-copy-id tantai@172.16.19.116

# 4. Chạy Ansible
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/setup-postgres.yml

# 5. Update inventory với static IP
vim inventory/hosts.yml
# Sửa ansible_host: 172.16.19.10

# 6. Verify
ping 172.16.19.10
ssh tantai@172.16.19.10
```

---

## Cải tiến trong tương lai

Để giảm số bước thủ công, có thể:

1. **Script tự động update inventory** sau khi Terraform chạy
2. **Makefile target tổng hợp** để chạy cả Terraform + Ansible
3. **Dynamic inventory** để Ansible tự động lấy IP từ Terraform state

Ví dụ Makefile target tổng hợp:
```makefile
deploy-postgres: apply-postgres
	@IP=$$(terraform output -raw postgres_ip); \
	sed -i '' "s/postgres:.*ansible_host:.*/postgres:\n      ansible_host: $$IP/" ansible/inventory/hosts.yml; \
	ssh-keyscan -H $$IP >> ~/.ssh/known_hosts 2>/dev/null; \
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/setup-postgres.yml
```
