# Kafka với Strimzi Operator

Kafka cluster (KRaft mode) trong namespace `kafka`, dùng Strimzi CRD. Broker/controller chỉ chạy khi **đã cài Strimzi Kafka Operator** (script `deploy.sh` làm đủ bước).

## Deploy nhanh (khuyến nghị)

```bash
cd k8s-manifests/kafka
chmod +x deploy.sh
./deploy.sh
```

Script: namespace → cài Strimzi operator → đợi Ready → apply cluster + Kafka UI. Đợi 2–3 phút rồi kiểm tra: `kubectl get pods,kafka -n kafka`.

## Deploy thủ công (nếu cần)

1. `kubectl apply -f 00-namespace.yaml`
2. Cài Strimzi operator (xem **`00-STRIMZI-OPERATOR.md`** – kubectl hoặc Helm)
3. Đợi operator pod Ready
4. `kubectl apply -f 01-kafka-cluster.yaml`
5. `kubectl apply -f 02-kafka-ui.yaml`

## Thông tin cluster (manifest trong repo)

- **Tên cluster:** `kafka-cluster` (trong `01-kafka-cluster.yaml`)
- **Kafka version:** 4.0.1
- **Mode:** KRaft (không Zookeeper)
- **Replicas:** 1 controller + 1 broker (KafkaNodePool)
- **Storage:** Longhorn (controller 5Gi, broker 10Gi)

## Thứ tự deploy (đã gộp trong `./deploy.sh`)

1. `00-namespace.yaml` → namespace `kafka`
2. Cài Strimzi operator (URL chính thức, có thể báo AlreadyExists – bỏ qua)
3. Đợi operator Ready
4. `01-kafka-cluster.yaml` → operator tạo broker/controller + services
5. `02-kafka-ui.yaml` → Kafka UI

## Access points

**External (LoadBalancer):**

- Bootstrap: `172.16.21.202:9094`
- Kafka UI: `172.16.21.203:8080`

**Internal (trong K8s):**

- Bootstrap: `kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092`

## Files trong thư mục

| File | Mô tả |
|------|--------|
| `00-namespace.yaml` | Namespace `kafka` |
| `00-STRIMZI-OPERATOR.md` | Hướng dẫn cài Strimzi operator (bắt buộc đọc trước) |
| `01-kafka-cluster.yaml` | Kafka CR + KafkaNodePool (controller, broker) |
| `02-kafka-ui.yaml` | Kafka UI deployment + LoadBalancer |
| `README.md` | File này |

## Management

### Kiểm tra status

```bash
kubectl get kafka,kafkanodepool -n kafka
kubectl get pods,pvc,svc -n kafka
```

### Tên pod (sau khi operator chạy)

- Controller: `kafka-cluster-controller-*`
- Broker: `kafka-cluster-kafka-*`
- Entity operator: `kafka-cluster-entity-operator-*`

### Create topic (KafkaTopic CR)

```bash
kubectl apply -f - <<EOF
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: test-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  partitions: 3
  replicas: 1
EOF
```

### Logs

```bash
# Operator
kubectl logs -n kafka -l name=strimzi-cluster-operator --tail=50

# Broker (tên pod có thể khác, xem kubectl get pods -n kafka)
kubectl logs kafka-cluster-kafka-0 -n kafka

# Controller
kubectl logs kafka-cluster-controller-0 -n kafka
```

### Scale

```bash
kubectl patch kafkanodepool broker -n kafka --type merge -p '{"spec":{"replicas":3}}'
kubectl patch kafkanodepool controller -n kafka --type merge -p '{"spec":{"replicas":3}}'
```

### Cleanup

```bash
# Xóa cluster (giữ PVC nếu cần)
kubectl delete kafka kafka-cluster -n kafka
kubectl delete kafkanodepool broker controller -n kafka

# Xóa hết kể cả PVC
kubectl delete namespace kafka
```

## Troubleshooting

- **Chỉ có Kafka UI, không có broker/controller:** Chưa cài Strimzi operator hoặc operator chưa chạy. Làm theo `00-STRIMZI-OPERATOR.md`.
- **Kafka UI không kết nối:** Đợi Kafka cluster Ready (operator đã tạo xong pods và service `kafka-cluster-kafka-bootstrap`).
- **Kiểm tra operator:**  
  `kubectl get pods -n kafka -l name=strimzi-cluster-operator`  
  `kubectl logs -n kafka -l name=strimzi-cluster-operator --tail=50`

---

**Kafka:** 4.0.1 (KRaft)  
**Manifest:** cluster name `kafka-cluster`, 1 controller + 1 broker, Longhorn storage.
