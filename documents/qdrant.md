# Qdrant Vector Database Setup Guide

> Vector database cho RAG (Retrieval-Augmented Generation) và AI applications

---

## 📋 Mục lục

1. [Tổng quan](#tổng-quan)
2. [Kiến trúc](#kiến-trúc)
3. [Deployment](#deployment)
4. [Quản lý Collections](#quản-lý-collections)
5. [Kết nối từ Application](#kết-nối-từ-application)
6. [Backup & Recovery](#backup--recovery)
7. [Troubleshooting](#troubleshooting)

---

## 🎯 Tổng quan

### Use Case

Qdrant được dùng cho:

- **RAG (Retrieval-Augmented Generation)**: Lưu trữ embeddings cho chatbot, Q&A systems
- **Semantic Search**: Tìm kiếm dựa trên ý nghĩa thay vì keyword
- **Recommendation Systems**: Gợi ý sản phẩm, nội dung tương tự
- **Image/Audio Search**: Tìm kiếm đa phương tiện

### Specs (Đồ án sinh viên)

- **VM**: 172.16.19.20
- **RAM**: 2-4GB (đủ cho RAG nhỏ, ~100K vectors)
- **Storage**: 20GB data disk
- **Version**: Qdrant latest
- **Ports**: 6333 (HTTP API), 6334 (gRPC)

---

## 🏗️ Kiến trúc

```
┌─────────────────────────────────────────────────────────┐
│                Qdrant VM (172.16.19.20)                 │
│                2-4GB RAM | 20GB Disk                    │
│                                                         │
│  ┌─────────────┐         ┌──────────────────────────┐  │
│  │ Boot Disk   │         │   Data Disk (20GB XFS)   │  │
│  │ /dev/sda    │         │   /mnt/qdrant_data       │  │
│  │             │         │                          │  │
│  │ - Ubuntu OS │         │   └── qdrant-stack/      │  │
│  │ - Docker    │         │       ├── storage/       │  │
│  └─────────────┘         │       ├── snapshots/     │  │
│                          │       └── docker-compose │  │
│                          └──────────────────────────┘  │
│                                     │                  │
│  ┌──────────────────────────────────┴─────────────┐    │
│  │    Docker Container: qdrant/qdrant:latest     │    │
│  │                                                │    │
│  │  Port 6333: HTTP API + Web Dashboard          │    │
│  │  Port 6334: gRPC API (high performance)       │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### Lợi ích Tách Boot & Data Disk

| Lợi ích             | Mô tả                                               |
| :------------------ | :-------------------------------------------------- |
| **I/O Performance** | Vector search cần I/O cao, XFS tối ưu hơn OverlayFS |
| **An toàn dữ liệu** | OS hỏng? Tháo Data Disk, gắn vào VM mới             |
| **Dễ mở rộng**      | Expand Data Disk không ảnh hưởng OS                 |
| **Backup đơn giản** | Snapshot Data Disk = backup toàn bộ vectors         |

---

## 🚀 Deployment

### Bước 1: Tạo VM (Terraform hoặc Manual)

**VM Specs:**

- vCPU: 2
- RAM: 4GB
- Boot Disk: 20GB
- Data Disk: 20GB (XFS)
- Network: DB-Network (172.16.19.0/24)
- IP: 172.16.19.20 (static)

### Bước 2: Setup Qdrant

```bash
cd ansible

# Deploy Qdrant
ansible-playbook playbooks/setup-qdrant.yml \
  -e "ansible_ssh_pass=21042004"
```

**Kết quả:**

- ✅ Docker installed
- ✅ Data disk mounted at `/mnt/qdrant_data`
- ✅ Qdrant container running
- ✅ HTTP API: `http://172.16.19.20:6333`
- ✅ gRPC API: `172.16.19.20:6334`
- ✅ Dashboard: `http://172.16.19.20:6333/dashboard`

### Bước 3: Verify

```bash
# Health check
curl http://172.16.19.20:6333/healthz

# Get cluster info
curl http://172.16.19.20:6333/cluster

# List collections
curl http://172.16.19.20:6333/collections
```

---

## 📊 Quản lý Collections

### Tạo Collection

```bash
curl -X PUT http://172.16.19.20:6333/collections/my_documents \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 384,
      "distance": "Cosine"
    }
  }'
```

**Giải thích:**

- `size: 384`: Dimension của embedding (ví dụ: all-MiniLM-L6-v2)
- `distance: Cosine`: Metric tính similarity (Cosine, Euclidean, Dot)

### Insert Vectors

```bash
curl -X PUT http://172.16.19.20:6333/collections/my_documents/points \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.1, 0.2, 0.3, ...],
        "payload": {
          "text": "This is a document",
          "source": "doc1.pdf"
        }
      }
    ]
  }'
```

### Search Vectors

```bash
curl -X POST http://172.16.19.20:6333/collections/my_documents/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, ...],
    "limit": 5,
    "with_payload": true
  }'
```

---

## 🔌 Kết nối từ Application

### Python (qdrant-client)

```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

# Connect to Qdrant
client = QdrantClient(host="172.16.19.20", port=6333)

# Create collection
client.create_collection(
    collection_name="my_documents",
    vectors_config=VectorParams(size=384, distance=Distance.COSINE),
)

# Insert vectors
client.upsert(
    collection_name="my_documents",
    points=[
        PointStruct(
            id=1,
            vector=[0.1, 0.2, 0.3, ...],  # 384 dimensions
            payload={"text": "Document content", "source": "doc1.pdf"}
        )
    ]
)

# Search
results = client.search(
    collection_name="my_documents",
    query_vector=[0.1, 0.2, 0.3, ...],
    limit=5
)

for result in results:
    print(f"Score: {result.score}, Text: {result.payload['text']}")
```

### Node.js (@qdrant/js-client-rest)

```javascript
const { QdrantClient } = require("@qdrant/js-client-rest");

const client = new QdrantClient({ host: "172.16.19.20", port: 6333 });

// Create collection
await client.createCollection("my_documents", {
  vectors: { size: 384, distance: "Cosine" },
});

// Insert vectors
await client.upsert("my_documents", {
  points: [
    {
      id: 1,
      vector: [0.1, 0.2, 0.3 /* ... */],
      payload: { text: "Document content" },
    },
  ],
});

// Search
const results = await client.search("my_documents", {
  vector: [0.1, 0.2, 0.3 /* ... */],
  limit: 5,
});
```

### LangChain Integration

```python
from langchain.vectorstores import Qdrant
from langchain.embeddings import HuggingFaceEmbeddings

# Initialize embeddings
embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")

# Connect to Qdrant
vectorstore = Qdrant(
    client=QdrantClient(host="172.16.19.20", port=6333),
    collection_name="my_documents",
    embeddings=embeddings,
)

# Add documents
vectorstore.add_texts(
    texts=["Document 1", "Document 2"],
    metadatas=[{"source": "doc1"}, {"source": "doc2"}]
)

# Search
results = vectorstore.similarity_search("query text", k=5)
```

---

## 💾 Backup & Recovery

### Manual Snapshot

```bash
# SSH vào Qdrant VM
ssh tantai@172.16.19.20

# Create snapshot
curl -X POST http://localhost:6333/collections/my_documents/snapshots

# List snapshots
curl http://localhost:6333/collections/my_documents/snapshots

# Download snapshot
curl http://localhost:6333/collections/my_documents/snapshots/snapshot_name \
  -o backup.snapshot
```

### Automated Backup Script

```bash
#!/bin/bash
# /opt/scripts/backup-qdrant.sh

BACKUP_DIR="/mnt/backup/qdrant"
RETENTION_DAYS=7

mkdir -p $BACKUP_DIR

# Get all collections
COLLECTIONS=$(curl -s http://localhost:6333/collections | jq -r '.result.collections[].name')

for COLLECTION in $COLLECTIONS; do
  # Create snapshot
  SNAPSHOT=$(curl -s -X POST http://localhost:6333/collections/$COLLECTION/snapshots | jq -r '.result.name')

  # Download snapshot
  curl -s http://localhost:6333/collections/$COLLECTION/snapshots/$SNAPSHOT \
    -o $BACKUP_DIR/${COLLECTION}_$(date +%Y%m%d).snapshot
done

# Cleanup old backups
find $BACKUP_DIR -name "*.snapshot" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $(date)"
```

**Setup Cronjob:**

```bash
# Chạy lúc 3:00 AM hàng ngày
0 3 * * * /opt/scripts/backup-qdrant.sh >> /var/log/qdrant-backup.log 2>&1
```

### Restore from Snapshot

```bash
# Upload snapshot
curl -X POST http://172.16.19.20:6333/collections/my_documents/snapshots/upload \
  -F 'snapshot=@backup.snapshot'

# Restore will happen automatically
```

---

## 🔍 Monitoring & Troubleshooting

### Check Container Status

```bash
ssh tantai@172.16.19.20
docker ps | grep qdrant
docker logs qdrant_prod
```

### Check Storage Usage

```bash
# On Qdrant VM
df -h /mnt/qdrant_data
du -sh /mnt/qdrant_data/qdrant-stack/storage/*
```

### Performance Metrics

```bash
# Get metrics
curl http://172.16.19.20:6333/metrics

# Collection info
curl http://172.16.19.20:6333/collections/my_documents
```

### Common Issues

#### 1. Out of Memory

**Triệu chứng:** Container restart, slow queries

**Giải pháp:**

```bash
# Increase VM RAM hoặc optimize collection
curl -X PATCH http://172.16.19.20:6333/collections/my_documents \
  -H "Content-Type: application/json" \
  -d '{
    "optimizers_config": {
      "indexing_threshold": 10000
    }
  }'
```

#### 2. Slow Search

**Triệu chứng:** Query > 1s

**Giải pháp:**

- Enable HNSW index (default)
- Reduce `ef` parameter
- Use quantization for large collections

```bash
curl -X PATCH http://172.16.19.20:6333/collections/my_documents \
  -H "Content-Type: application/json" \
  -d '{
    "hnsw_config": {
      "m": 16,
      "ef_construct": 100
    }
  }'
```

---

## 📚 Tài liệu tham khảo

- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [Qdrant API Reference](https://qdrant.github.io/qdrant/redoc/index.html)
- [LangChain Qdrant Integration](https://python.langchain.com/docs/integrations/vectorstores/qdrant)
- [Qdrant Performance Tuning](https://qdrant.tech/documentation/guides/optimize/)

---

**Version:** 1.0  
**Qdrant Version:** latest  
**Last Updated:** 2026-02-08  
**Use Case:** RAG for student projects
