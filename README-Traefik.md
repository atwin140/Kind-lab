# Traefik Ingress Controller - Complete Guide

A comprehensive guide to deploying and using Traefik as an ingress controller in Kubernetes, deployed via FluxCD GitOps.

## Table of Contents

- [What is Traefik?](#what-is-traefik)
- [How Traefik Works as Ingress](#how-traefik-works-as-ingress)
- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Traefik Components Explained](#traefik-components-explained)
- [Creating an Ingress Route](#creating-an-ingress-route)
- [Testing Your Deployment](#testing-your-deployment)
- [Monitoring Traefik](#monitoring-traefik)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)

---

## What is Traefik?

**Traefik** (pronounced "traffic") is a modern, cloud-native reverse proxy and load balancer designed specifically for microservices and containerized applications. It's a popular alternative to NGINX Ingress Controller.

### Key Features

- **Automatic Service Discovery** - Discovers services automatically without manual configuration
- **Dynamic Configuration** - Updates routing rules in real-time without restarts
- **Native Kubernetes Support** - First-class support for Kubernetes Ingress and CRDs
- **Let's Encrypt Integration** - Built-in automatic SSL/TLS certificate management
- **Middleware Support** - Authentication, rate limiting, circuit breakers, and more
- **Multiple Protocols** - HTTP, HTTPS, TCP, UDP, gRPC, WebSocket
- **Elegant Dashboard** - Built-in web UI for monitoring and debugging
- **Metrics & Observability** - Prometheus, DataDog, Jaeger integration

---

## How Traefik Works as Ingress

### The Ingress Pattern

In Kubernetes, an **Ingress** is an API object that manages external access to services in a cluster, typically HTTP/HTTPS. An **Ingress Controller** is the component that fulfills the Ingress rules.

Think of it like this:
- **Services** = Backend applications (like your web servers)
- **Ingress Rules** = Traffic routing configuration (which domain goes where)
- **Ingress Controller (Traefik)** = The traffic director making it all happen

### Traffic Flow

```
External Request (browser/curl)
         ↓
   [Port 80 - HTTP] ← Entry point to cluster
         ↓
   [Traefik Pod] ← Ingress Controller
         ↓
   Routing Decision (based on hostname, path, headers)
         ↓
   [Backend Service] ← Your application
         ↓
   [Application Pods] ← Actual workload
```

### How Traefik Makes Decisions

Traefik examines incoming HTTP requests and routes them based on:

1. **Hostname** - `app1.kind.local` → Service A, `app2.kind.local` → Service B
2. **Path** - `/api` → API Service, `/blog` → Blog Service
3. **Headers** - Custom routing based on HTTP headers
4. **Middleware** - Apply authentication, rate limiting, etc.

### The Air Traffic Controller Analogy

Imagine Traefik as an **air traffic controller** at a busy airport:

- **Incoming planes** = HTTP requests from users
- **Runways** = Your backend services (nginx, api, database, etc.)
- **Flight paths** = Ingress rules (routing configuration)
- **Control tower** = Traefik dashboard (monitoring)

Just like an air traffic controller:
- Traefik **directs traffic** safely to the right destination
- It **monitors everything** in real-time
- It **handles multiple requests** simultaneously
- It ensures **safe landings** (successful connections)
- It can **redirect flights** if a runway is down (automatic failover)

---

## Architecture Overview

### Components in This Deployment

```
┌─────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                  │
│                                                      │
│  ┌────────────────────────────────────────────┐    │
│  │          traefik namespace                  │    │
│  │                                             │    │
│  │  ┌──────────────────────────────────┐      │    │
│  │  │   Traefik Deployment             │      │    │
│  │  │   - Ingress Controller           │      │    │
│  │  │   - Dynamic config loading       │      │    │
│  │  │   - Dashboard                    │      │    │
│  │  └──────────────────────────────────┘      │    │
│  │                                             │    │
│  │  ┌──────────────────────────────────┐      │    │
│  │  │   Service (LoadBalancer)         │      │    │
│  │  │   - Web entry point (80)         │      │    │
│  │  │   - Dashboard (8080)             │      │    │
│  │  └──────────────────────────────────┘      │    │
│  │                                             │    │
│  └────────────────────────────────────────────┘    │
│                                                      │
│  ┌────────────────────────────────────────────┐    │
│  │          nginx namespace                    │    │
│  │                                             │    │
│  │  ┌──────────────────────────────────┐      │    │
│  │  │   NGINX Deployment               │      │    │
│  │  │   - Web server                   │      │    │
│  │  │   - ConfigMap with HTML          │      │    │
│  │  └──────────────────────────────────┘      │    │
│  │                                             │    │
│  │  ┌──────────────────────────────────┐      │    │
│  │  │   Ingress Resource               │      │    │
│  │  │   - Routes traffic from Traefik  │      │    │
│  │  └──────────────────────────────────┘      │    │
│  │                                             │    │
│  └────────────────────────────────────────────┘    │
│                                                      │
└─────────────────────────────────────────────────────┘

External Access: http://localhost:80
```

---

## Prerequisites

Before deploying Traefik, ensure you have:

- ✅ KinD cluster running (3 nodes recommended)
- ✅ FluxCD installed and connected to Git repository
- ✅ kubectl configured
- ✅ Port 80 available on localhost (configured in kind-cluster.yaml)

Verify:
```bash
kubectl get nodes
kubectl get pods -n flux-system
```

---

## Deployment

### Option 1: Automatic Deployment via FluxCD (Recommended)

If FluxCD is syncing the `./components` directory, Traefik will be deployed automatically.

**Verify FluxCD is syncing:**
```bash
kubectl get gitrepository -n flux-system
kubectl get kustomization -n flux-system
```

**Force a sync (optional):**
```bash
kubectl annotate gitrepository kind-lab \
  -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)"
```

### Option 2: Manual Deployment

Apply the Traefik components directly:

```bash
kubectl apply -k components/traefik/
```

### Verify Deployment

Check that Traefik is running:

```bash
# Check namespace
kubectl get ns traefik

# Check pods
kubectl get pods -n traefik

# Check service
kubectl get svc -n traefik

# Wait for Traefik to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=traefik \
  -n traefik --timeout=2m
```

---

## Traefik Components Explained

### 1. Namespace (`namespace.yaml`)

Creates an isolated `traefik` namespace:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
```

### 2. ServiceAccount (`serviceaccount.yaml`)

Provides identity for Traefik pods to interact with Kubernetes API:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik
  namespace: traefik
```

### 3. ClusterRole & ClusterRoleBinding (`rbac.yaml`)

Grants Traefik permissions to:
- Watch for Ingress resources
- Discover Services and Endpoints
- Read configuration from ConfigMaps and Secrets

### 4. ConfigMap (`configmap.yaml`)

Contains the creative HTML page showing Traefik directing traffic - **a plane being guided by the Traefik air traffic controller**!

### 5. Deployment (`deployment.yaml`)

The main Traefik controller that:
- Listens on ports 80 (HTTP) and 8080 (dashboard)
- Watches Kubernetes API for Ingress resources
- Automatically configures routing based on Ingress rules
- Serves the Traefik dashboard

### 6. Service (`service.yaml`)

Exposes Traefik via LoadBalancer with hostPort binding on port 80 so external traffic can reach it directly on standard HTTP port.

---

## Creating an Ingress Route

### Basic Ingress Example

Create a simple Ingress to route traffic through Traefik:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: my-app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: myapp.kind.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-service
            port:
              number: 80
```

### Path-Based Routing

Route different paths to different services:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-based-ingress
  namespace: default
spec:
  ingressClassName: traefik
  rules:
  - host: mysite.kind.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### Host-Based Routing

Route different domains to different services:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-based-ingress
  namespace: default
spec:
  ingressClassName: traefik
  rules:
  - host: api.kind.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
  - host: blog.kind.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: blog-service
            port:
              number: 80
```

---

## Testing Your Deployment

### Access the Traefik Welcome Page

Open your browser or use curl:

```bash
curl http://localhost:80
# or simply
curl http://localhost
```

You should see a creative HTML page showing a plane being directed by Traefik!

### Access the Traefik Dashboard

The dashboard provides real-time visibility into:
- Active routes and rules
- Backend services
- Middleware configuration
- Request metrics

```bash
# Port-forward the dashboard
kubectl port-forward -n traefik svc/traefik 8080:8080

# Open in browser
open http://localhost:8080/dashboard/
```

**Note:** The dashboard is on port 8080 (via port-forward), while the main Traefik ingress is on port 80.

### Test Routing Through an Ingress

If you've created an Ingress with host-based routing:

```bash
# With mDNS configured (see kubevip setup), domains resolve automatically:
curl http://myapp.kind.local

# Or manually add to /etc/hosts if not using mDNS:
echo "127.0.0.1 myapp.kind.local" | sudo tee -a /etc/hosts
curl http://myapp.kind.local
```

---

## Monitoring Traefik

### Check Traefik Logs

View real-time logs from Traefik:

```bash
# Get pod name
TRAEFIK_POD=$(kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}')

# View logs
kubectl logs -n traefik $TRAEFIK_POD

# Follow logs
kubectl logs -n traefik $TRAEFIK_POD -f
```

### View Ingress Resources

List all Ingress resources across namespaces:

```bash
kubectl get ingress -A
```

Describe a specific Ingress:

```bash
kubectl describe ingress <ingress-name> -n <namespace>
```

### Check Service Discovery

See what services Traefik has discovered:

```bash
kubectl get endpoints -A
kubectl get svc -A
```

### Dashboard Monitoring

The Traefik dashboard shows:
- **Routers** - Active routing rules
- **Services** - Backend services and health
- **Middlewares** - Applied policies
- **Entrypoints** - Listening ports

---

## Troubleshooting

### Issue: Traefik Pod Not Starting

**Check pod status:**
```bash
kubectl get pods -n traefik
kubectl describe pod -n traefik <pod-name>
```

**Common causes:**
- RBAC permissions missing
- Port conflicts
- Image pull errors

### Issue: Ingress Not Routing Traffic

**Check Ingress status:**
```bash
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>
```

**Verify:**
- IngressClassName is set to `traefik`
- Backend service exists and has endpoints
- Traefik has RBAC permissions

**Check Traefik logs:**
```bash
kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i error
```

### Issue: Cannot Access on Port 80

**Verify service and hostPort configuration:**
```bash
kubectl get svc -n traefik
kubectl get pods -n traefik -o wide
```

Ensure:
- Port 80 is configured in kind-cluster.yaml with `extraPortMappings`
- Traefik pod has `hostPort: 80` in deployment
- Traefik pod is running on the control-plane node (where port mapping exists)
- No other service is using port 80

**Test locally:**
```bash
curl -v http://localhost:80
# Check if pod is on correct node
kubectl get pods -n traefik -o wide
```

### Issue: 404 Not Found

**Possible causes:**
- Ingress rule doesn't match the request (host/path)
- Backend service has no healthy endpoints
- Service selector doesn't match pod labels

**Debug:**
```bash
# Check if backend pods are running
kubectl get pods -n <namespace>

# Check if service has endpoints
kubectl get endpoints -n <namespace>

# Verify Ingress configuration
kubectl get ingress <name> -n <namespace> -o yaml
```

### Issue: 502 Bad Gateway

**This means Traefik can't reach the backend.**

**Check:**
```bash
# Verify backend pods are running
kubectl get pods -n <namespace> -l <selector>

# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Test service directly
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://<service-name>.<namespace>.svc.cluster.local:<port>
```

---

## Advanced Configuration

### Enable Access Logs

Update Traefik deployment to enable request logging:

```yaml
args:
  - --accesslog=true
  - --accesslog.filepath=/var/log/traefik/access.log
```

### Add Middleware

Create middleware for authentication, rate limiting, etc:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: traefik
spec:
  rateLimit:
    average: 100
    burst: 50
```

Apply to Ingress:
```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: traefik-rate-limit@kubernetescrd
```

### HTTPS with Let's Encrypt

Configure automatic TLS certificates:

```yaml
args:
  - --certificatesresolvers.letsencrypt.acme.email=admin@kind.local
  - --certificatesresolvers.letsencrypt.acme.storage=/data/acme.json
  - --certificatesresolvers.letsencrypt.acme.tlschallenge=true
```

Use in Ingress:
```yaml
spec:
  tls:
  - hosts:
    - myapp.kind.local
    secretName: myapp-tls
```

### Custom Entry Points

Define additional ports:

```yaml
args:
  - --entrypoints.websecure.address=:443
  - --entrypoints.metrics.address=:9090
```

### Prometheus Metrics

Enable metrics endpoint:

```yaml
args:
  - --metrics.prometheus=true
  - --metrics.prometheus.entrypoint=metrics
```

---

## Comparison: Traefik vs NGINX Ingress

| Feature | Traefik | NGINX Ingress |
|---------|---------|---------------|
| Configuration | Automatic via Kubernetes API | Requires more manual config |
| Dashboard | Built-in web UI | External dashboards needed |
| Dynamic Updates | Real-time, no reload | Requires reload |
| Let's Encrypt | Native support | Plugin required |
| Learning Curve | Easier for beginners | Steeper, more powerful |
| Performance | Good for most workloads | Slightly better for high load |
| Middleware | Rich built-in middleware | Annotations-based |

---

## Resources

- **Traefik Documentation**: https://doc.traefik.io/traefik/
- **Traefik Kubernetes Guide**: https://doc.traefik.io/traefik/providers/kubernetes-ingress/
- **GitHub Repository**: https://github.com/traefik/traefik
- **Community Forum**: https://community.traefik.io/

---

## Summary

You've learned:
✅ What Traefik is and how it works as an ingress controller  
✅ The air traffic controller analogy for understanding traffic routing  
✅ How to deploy Traefik via FluxCD  
✅ Creating Ingress resources for routing  
✅ Monitoring and troubleshooting techniques  
✅ Advanced configuration options  

Traefik now acts as your cluster's traffic director, automatically routing external requests to the right services based on hostnames and paths!
