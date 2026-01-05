# Jinja2 Templates trong Ansible

> Hướng dẫn sử dụng Jinja2 templates (.j2) để tạo cấu hình động

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Mục lục

- [Jinja2 Template là gì?](#jinja2-template-là-gì)
- [Cách hoạt động](#cách-hoạt-động)
- [Cú pháp cơ bản](#cú-pháp-cơ-bản)
- [Ví dụ thực tế trong project](#ví-dụ-thực-tế-trong-project)
- [Best Practices](#best-practices)
- [Khi nào nên/không nên dùng](#khi-nào-nênkhông-nên-dùng)

---

### Jinja2 Template là gì?

**Jinja2 template (.j2)** là file khuôn mẫu cho phép tạo nội dung động bằng cách:

- Thay thế biến bằng giá trị thực
- Sử dụng logic điều kiện và vòng lặp
- Áp dụng filters để xử lý dữ liệu

```
Template (.j2) + Variables + Logic → File cấu hình cuối cùng
```

---

### Cách hoạt động

```yaml
# Ansible task
- name: Generate config file
  template:
    src: app.conf.j2 # Template file
    dest: /etc/app.conf # Output file
```

**Workflow:**

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Template       │    │  Ansible        │    │  Target Server  │
│  app.conf.j2    │───►│  Render         │───►│  /etc/app.conf  │
│  + Variables    │    │  Process        │    │  (final config) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

### Cú pháp cơ bản

#### Variables

```jinja2
server_name {{ domain_name }}
port {{ app_port }}
debug {{ debug_mode }}
```

#### Conditionals

```jinja2
{% if environment == "production" %}
log_level = ERROR
{% else %}
log_level = DEBUG
{% endif %}
```

#### Loops

```jinja2
{% for server in backend_servers %}
upstream {{ server.name }} {
    server {{ server.ip }}:{{ server.port }};
}
{% endfor %}
```

#### Filters

```jinja2
# Default values
database_host: {{ db_host | default('localhost') }}

# String manipulation
app_name: {{ service_name | upper }}

# List operations
allowed_ips: {{ ip_list | join(',') }}

# Password hashing
user_password: {{ plain_password | password_hash('sha512') }}
```

---

### Ví dụ thực tế trong project

#### 1. PostgreSQL Docker Compose

**File:** `ansible/templates/postgres/docker-compose.yml.j2`

```yaml
services:
  postgres:
    image: postgres:{{ postgres_version }}-alpine
    container_name: pg{{ postgres_version }}_prod
    environment:
      - POSTGRES_PASSWORD={{ postgres_password }}
    volumes:
      - ./data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
```

**Variables:**

```yaml
postgres_version: "15"
postgres_password: "SecurePassword123!"
```

**Result:** `docker-compose.yml`

```yaml
services:
  postgres:
    image: postgres:15-alpine
    container_name: pg15_prod
    environment:
      - POSTGRES_PASSWORD=SecurePassword123!
    volumes:
      - ./data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
```

#### 2. MinIO Environment File

**File:** `ansible/templates/minio/.env.j2`

```bash
MINIO_ROOT_USER={{ minio_root_user }}
MINIO_ROOT_PASSWORD={{ minio_root_password }}
MINIO_VOLUMES="/data"
```

**Variables:**

```yaml
minio_root_user: "admin"
minio_root_password: "SuperSecretPassword123!"
```

**Result:** `.env`

```bash
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=SuperSecretPassword123!
MINIO_VOLUMES="/data"
```

#### 3. Zot Registry Config

**File:** `ansible/templates/minio/zot-config.json.j2`

```json
{
  "storage": {
    "storageDriver": {
      "endpoint": "minio:9000",
      "accesskey": "{{ minio_root_user }}",
      "secretkey": "{{ minio_root_password }}",
      "secure": false
    }
  },
  "http": {
    "address": "0.0.0.0",
    "port": "5000"
  }
}
```

#### 4. Conditional Configuration

**File:** `nginx.conf.j2`

```nginx
server {
    listen {{ nginx_port }};
    server_name {{ domain_name }};

    {% if ssl_enabled %}
    listen 443 ssl;
    ssl_certificate {{ ssl_cert_path }};
    ssl_certificate_key {{ ssl_key_path }};
    {% endif %}

    location / {
        {% if environment == "development" %}
        proxy_pass http://localhost:3000;
        {% else %}
        proxy_pass http://{{ backend_servers | join(':8080;') }}:8080;
        {% endif %}
    }
}
```

---

### Best Practices

#### ✅ DO

**1. Sử dụng default values**

```jinja2
database_port: {{ db_port | default(5432) }}
log_level: {{ app_log_level | default('INFO') }}
```

**2. Tên biến rõ ràng**

```jinja2
# Good
{{ postgres_max_connections }}
{{ nginx_worker_processes }}

# Bad
{{ max_conn }}
{{ workers }}
```

**3. Nhóm biến theo chức năng**

```yaml
# Group related variables
postgres_config:
  version: "15"
  port: 5432
  max_connections: 200

nginx_config:
  worker_processes: 4
  client_max_body_size: "50M"
```

**4. Sử dụng comments**

```jinja2
{# PostgreSQL configuration for {{ environment }} environment #}
max_connections = {{ postgres_max_connections }}

{# Enable SSL only in production #}
{% if environment == "production" %}
ssl = on
{% endif %}
```

#### ❌ DON'T

**1. Logic phức tạp trong template**

```jinja2
{# Bad - too complex #}
{% for server in servers %}
  {% if server.role == "primary" and server.status == "active" %}
    {% for db in server.databases %}
      {% if db.size > 1000 and db.backup_enabled %}
        # Complex logic here...
      {% endif %}
    {% endfor %}
  {% endif %}
{% endfor %}
```

**2. Hardcode secrets**

```jinja2
{# Bad #}
password = "hardcoded_password"

{# Good #}
password = {{ vault_password }}
```

**3. Quá nhiều điều kiện lồng nhau**

```jinja2
{# Bad #}
{% if env == "prod" %}
  {% if ssl == true %}
    {% if cert_exists %}
      # Too nested
    {% endif %}
  {% endif %}
{% endif %}
```

---

### Khi nào nên/không nên dùng

#### ✅ Nên dùng khi:

- **Cấu hình khác nhau theo môi trường**

  ```jinja2
  # dev.yml: debug = true
  # prod.yml: debug = false
  debug = {{ debug_mode }}
  ```

- **Danh sách động**

  ```jinja2
  {% for server in database_servers %}
  server {{ server.ip }}:{{ server.port }};
  {% endfor %}
  ```

- **Conditional features**
  ```jinja2
  {% if monitoring_enabled %}
  include /etc/nginx/monitoring.conf;
  {% endif %}
  ```

#### ❌ Không nên dùng khi:

- **File static không có biến**

  ```yaml
  # Use copy module instead
  - name: Copy static file
    copy:
      src: static-config.conf
      dest: /etc/app/config.conf
  ```

- **Logic business phức tạp**
  ```yaml
  # Handle in Ansible tasks, not template
  - name: Calculate optimal settings
    set_fact:
      optimal_workers: "{{ ansible_processor_vcpus * 2 }}"
  ```

---

### So sánh với alternatives

| Method              | Use Case            | Pros               | Cons             |
| ------------------- | ------------------- | ------------------ | ---------------- |
| **Jinja2 Template** | Dynamic config      | Flexible, reusable | Learning curve   |
| **Copy Module**     | Static files        | Simple, fast       | No customization |
| **Lineinfile**      | Single line changes | Precise            | Limited scope    |
| **Blockinfile**     | Block insertions    | Good for additions | Can be messy     |

---

## English

### Table of Contents

- [What is Jinja2 Template?](#what-is-jinja2-template)
- [How it Works](#how-it-works)
- [Basic Syntax](#basic-syntax)
- [Real Examples from Project](#real-examples-from-project)
- [Best Practices](#best-practices-1)
- [When to Use/Not Use](#when-to-usenot-use)

---

### What is Jinja2 Template?

**Jinja2 templates (.j2)** are template files that generate dynamic content by:

- Substituting variables with actual values
- Using conditional logic and loops
- Applying filters for data processing

```
Template (.j2) + Variables + Logic → Final configuration file
```

---

### How it Works

```yaml
# Ansible task
- name: Generate config file
  template:
    src: app.conf.j2 # Template file
    dest: /etc/app.conf # Output file
```

---

### Basic Syntax

#### Variables

```jinja2
server_name {{ domain_name }}
port {{ app_port }}
```

#### Conditionals

```jinja2
{% if environment == "production" %}
log_level = ERROR
{% else %}
log_level = DEBUG
{% endif %}
```

#### Loops

```jinja2
{% for server in backend_servers %}
upstream {{ server.name }} {
    server {{ server.ip }}:{{ server.port }};
}
{% endfor %}
```

#### Filters

```jinja2
database_host: {{ db_host | default('localhost') }}
app_name: {{ service_name | upper }}
allowed_ips: {{ ip_list | join(',') }}
```

---

### Real Examples from Project

#### PostgreSQL Docker Compose

```yaml
# ansible/templates/postgres/docker-compose.yml.j2
services:
  postgres:
    image: postgres:{{ postgres_version }}-alpine
    environment:
      - POSTGRES_PASSWORD={{ postgres_password }}
```

#### MinIO Environment

```bash
# ansible/templates/minio/.env.j2
MINIO_ROOT_USER={{ minio_root_user }}
MINIO_ROOT_PASSWORD={{ minio_root_password }}
```

---

### Best Practices

#### ✅ DO

- Use default values: `{{ port | default(8080) }}`
- Clear variable names: `{{ postgres_max_connections }}`
- Group related variables
- Add comments for clarity

#### ❌ DON'T

- Complex logic in templates
- Hardcode secrets
- Too many nested conditions

---

### When to Use/Not Use

#### ✅ Use when:

- Configuration varies by environment
- Dynamic lists or conditional features
- Need variable substitution

#### ❌ Don't use when:

- Static files without variables
- Complex business logic
- Simple file copying
