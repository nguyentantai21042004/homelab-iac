# Qdrant Vector Database

Qdrant là Vector Database hiệu năng cao, viết bằng Rust, được triển khai trên VM riêng trong DB Network.

## Thông tin kết nối

| Service   | Endpoint                             |
| --------- | ------------------------------------ |
| HTTP API  | `http://172.16.19.20:6333`           |
| gRPC      | `172.16.19.20:6334`                  |
| Dashboard | `http://172.16.19.20:6333/dashboard` |

## Triển khai

### 1. Tạo VM (Terraform)

```bash
cd terraform
terraform plan
terraform apply
```

### 2. Setup Qdrant (Ansible)

```bash
cd ansible

# Setup VM cơ bản (network, SSH)
ansible-playbook playbooks/setup-vm.yml -l qdrant

# Setup Qdrant
ansible-playbook playbooks/setup-qdrant.yml
```

## Sử dụng

### Python Client

```bash
pip install qdrant-client
```

```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

# Kết nối
client = QdrantClient(url="http://172.16.19.20", port=6333)

# Tạo collection (vector 384 chiều - sentence-transformers)
client.recreate_collection(
    collection_name="documents",
    vectors_config=VectorParams(size=384, distance=Distance.COSINE),
)

# Thêm dữ liệu
client.upsert(
    collection_name="documents",
    points=[
        PointStruct(
            id=1,
            vector=[0.1] * 384,  # Vector từ embedding model
            payload={"title": "Document 1", "category": "tech"}
        ),
    ]
)

# Tìm kiếm với filter
results = client.search(
    collection_name="documents",
    query_vector=[0.1] * 384,
    query_filter={"must": [{"key": "category", "match": {"value": "tech"}}]},
    limit=5
)
```

## Backup & Restore

### Tạo Snapshot

```bash
# Qua API
curl -X POST "http://172.16.19.20:6333/collections/documents/snapshots"
```

### Restore

```bash
# Copy snapshot vào thư mục snapshots
scp backup.snapshot tantai@172.16.19.20:/mnt/qdrant_data/qdrant-stack/snapshots/

# Restore qua API
curl -X PUT "http://172.16.19.20:6333/collections/documents/snapshots/recover" \
  -H "Content-Type: application/json" \
  -d '{"location": "/qdrant/snapshots/backup.snapshot"}'
```

## Bảo mật

Để bật API Key authentication, thêm vào `ansible/group_vars/all/vault.yml`:

```yaml
vault_qdrant_api_key: "your-secure-api-key"
```

Sau đó chạy lại playbook:

```bash
ansible-playbook playbooks/setup-qdrant.yml
```

Client sẽ cần thêm API key:

```python
client = QdrantClient(
    url="http://172.16.19.20",
    port=6333,
    api_key="your-secure-api-key"
)
```

## Monitoring

- Dashboard UI: `http://172.16.19.20:6333/dashboard`
- Health check: `curl http://172.16.19.20:6333/readyz`
- Metrics: `curl http://172.16.19.20:6333/metrics`
