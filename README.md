# Online Boutique on EKS 🛍️

A production-grade deployment of [Google's Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) — a 10-service microservices demo app — on AWS EKS using industry-standard tooling.

## Architecture

```
                        ┌──────────────────────────────────────────┐
                        │              AWS EKS Cluster              │
                        │                                           │
 Internet  ──────────►  │  ingress-nginx  ──────►  frontend        │
 (HTTPS)               │  (LoadBalancer)           │               │
                        │                           ▼               │
                        │            ┌──────────────────────────┐   │
                        │            │     Microservices         │   │
                        │            │  cartservice              │   │
                        │            │  checkoutservice          │   │
                        │            │  productcatalogservice    │   │
                        │            │  currencyservice          │   │
                        │            │  paymentservice           │   │
                        │            │  shippingservice          │   │
                        │            │  emailservice             │   │
                        │            │  recommendationservice    │   │
                        │            │  adservice                │   │
                        │            │  redis-cart               │   │
                        │            └──────────────────────────┘   │
                        │                                           │
                        │  monitoring/   cert-manager   sealed-     │
                        │  (Prometheus   (TLS auto)     secrets     │
                        │   + Grafana)                              │
                        └──────────────────────────────────────────┘
```

## Stack

| Layer | Tool |
|---|---|
| Cloud | AWS |
| Kubernetes | EKS |
| Infrastructure as Code | Terraform |
| Package manager | Helm |
| CI/CD | GitHub Actions (OIDC — no long-lived keys) |
| Container registry | Amazon ECR |
| Ingress | ingress-nginx |
| TLS | cert-manager + Let's Encrypt |
| Secrets | Bitnami Sealed Secrets |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana) |
| Autoscaling | Horizontal Pod Autoscaler |

## Live Demo

- **App:** https://shop.yourdomain.com
- **Grafana:** https://grafana.yourdomain.com

---

## Getting Started

### Prerequisites

```bash
brew install terraform awscli kubectl helm kubeseal
aws configure
```

### 1. Configure your variables

Update `infrastructure/terraform.tfvars` with your GitHub username and preferred region. Update `helm/online-boutique/values-prod.yaml` and `monitoring/prometheus-values.yaml` with your domain. Update `monitoring/cluster-issuer.yaml` with your email.

### 2. Provision Infrastructure

```bash
make init
make plan    # review what will be created
make apply
```

Once complete, copy the `github_actions_role_arn` output and add it as `AWS_ROLE_ARN` in your GitHub repo under Settings → Secrets → Actions.

### 3. Connect kubectl

```bash
make kubeconfig
```

### 4. Bootstrap the cluster (one-time)

```bash
make bootstrap
```

This installs cert-manager, ingress-nginx, Sealed Secrets, and the Let's Encrypt ClusterIssuers.

### 5. Deploy Monitoring

```bash
make monitoring
```

### 6. Deploy the App

```bash
make deploy
```

Or just push to `main` — GitHub Actions handles it automatically from here. 🚀

### 7. Point Your Domain to the Load Balancer

```bash
make lb   # prints the LoadBalancer hostname
```

Create a CNAME record in Route 53 (or your DNS provider):
- `shop.yourdomain.com` → `<load-balancer-hostname>`
- `grafana.yourdomain.com` → `<load-balancer-hostname>`

### Sealing a secret

```bash
make seal-secret NAME=online-boutique-secrets KEY=SOME_KEY VALUE=somevalue
```

---

## Repository Structure

```
.
├── .github/workflows/
│   ├── build-push.yml      # Build Docker images → ECR
│   └── deploy.yml          # Helm deploy → EKS
├── helm/online-boutique/
│   ├── Chart.yaml
│   ├── values.yaml         # Default values for all 10 services
│   ├── values-prod.yaml    # Production overrides
│   └── templates/
│       ├── deployments.yaml
│       ├── services.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml
│       ├── rbac.yaml
│       └── sealed-secrets.yaml
├── monitoring/
│   ├── prometheus-values.yaml
│   └── cluster-issuer.yaml
├── infrastructure/         # Terraform for EKS + ECR + OIDC
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── README.md
```

---

## Key Design Decisions

**OIDC instead of access keys** — GitHub Actions authenticates to AWS via OpenID Connect. No long-lived credentials stored anywhere.

**Sealed Secrets** — Encrypted secrets are safe to commit to Git. The Sealed Secrets controller in the cluster is the only thing that can decrypt them.

**Helm with separate prod values** — A single chart deploys everywhere; environment differences live in `values-prod.yaml`.

**HPA on frontend** — The entry point scales automatically under load. Resource requests/limits are set on every container.

**cert-manager + Let's Encrypt** — TLS certificates are provisioned and rotated automatically. No manual certificate management.

---

## Monitoring

After deployment, access Grafana at `https://grafana.yourdomain.com` (default login: `admin` / `changeme` — change this).

Preloaded dashboards:
- Kubernetes Cluster Overview
- Kubernetes Pod metrics

---

## License

MIT