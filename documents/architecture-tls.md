# TLS Architecture - API Gateway Centralized

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
│                           (HTTPS Traffic)                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     API GATEWAY (192.168.1.21)                               │
│                         Traefik v3.x                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    TLS TERMINATION                                   │    │
│  │              Let's Encrypt Certificates                              │    │
│  │         All *.tantai.dev subdomains                                  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  Routing (HTTP after TLS termination):                                      │
│  ├── dashboard.tantai.dev  → api@internal (Traefik Dashboard)               │
│  ├── storage.tantai.dev    → 172.16.21.10:9001 (MinIO)                      │
│  ├── registry.tantai.dev   → 172.16.21.10:5000 (ZOT)                        │
│  ├── ci.tantai.dev         → 172.16.21.21:8000 (Woodpecker)                 │
│  └── tantai.dev            → 172.16.21.100:80 (K3s VIP)                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                          HTTP (plain, no TLS)
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      K3S CLUSTER (172.16.21.100 VIP)                        │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    K3S TRAEFIK (HTTP only)                          │    │
│  │              Routes based on Host header                             │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  Internal Routing:                                                          │
│  └── tantai.dev → portfolio service (pet-projects namespace)                │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Points

### API Gateway (192.168.1.21)

- TLS termination for ALL \*.tantai.dev domains
- Certificate management via Let's Encrypt ACME HTTP-01
- Routes to external services (MinIO, ZOT, Woodpecker)
- Forwards HTTP to K3s for cluster services

### K3s Traefik (172.16.21.100)

- HTTP routing only - no TLS
- Routes based on Host header from API Gateway
- No cert-manager needed for external domains

## Adding New Services

### External Service (outside K3s)

Edit `ansible/templates/traefik/dynamic_conf.yml.j2`:

```yaml
http:
  routers:
    new-service:
      rule: "Host(`newservice.tantai.dev`)"
      service: new-service
      entryPoints:
        - websecure
      middlewares:
        - forwarded-headers
      tls:
        certResolver: letsencrypt

  services:
    new-service:
      loadBalancer:
        servers:
          - url: "http://172.16.21.XX:PORT"
```

Apply: `ansible-playbook -i inventory/hosts.yml playbooks/setup-api-gateway.yml`

### K3s Service

1. Add router in API Gateway (for new subdomain):

```yaml
# In dynamic_conf.yml.j2
k3s-newapp:
  rule: "Host(`newapp.tantai.dev`)"
  service: k3s-service
  entryPoints:
    - websecure
  middlewares:
    - forwarded-headers
  tls:
    certResolver: letsencrypt
```

2. Create Ingress in K3s (HTTP only):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: newapp-ingress
  namespace: your-namespace
spec:
  ingressClassName: traefik
  rules:
    - host: newapp.tantai.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: newapp-service
                port:
                  number: 80
```

**Note:** No TLS section in K3s Ingress - API Gateway handles TLS.

## Certificate Management

Location: `/opt/traefik/acme.json` on API Gateway

Check certificates:

```bash
ssh tantai@192.168.1.21 "cat /opt/traefik/acme.json | jq '.letsencrypt.Certificates[].domain.main'"
```
