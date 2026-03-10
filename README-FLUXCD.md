# FluxCD on Kubernetes (KinD) - Complete Guide

This guide walks through deploying FluxCD on a local Kubernetes cluster using Kubernetes in Docker (KinD), then connecting it to a GitHub repository for GitOps-based continuous deployment.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Step-by-Step Setup](#step-by-step-setup)
  - [1. Create KinD Cluster](#1-create-kind-cluster)
  - [2. Deploy FluxCD](#2-deploy-fluxcd)
  - [3. Connect to Git Repository](#3-connect-to-git-repository)
  - [4. Verify Deployment](#4-verify-deployment)
- [Testing Your Deployment](#testing-your-deployment)
- [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
- [Advanced Configuration](#advanced-configuration)
- [Useful Aliases](#useful-aliases)

---

## Overview

This lab demonstrates:
- Creating a multi-node Kubernetes cluster using KinD
- Installing FluxCD for GitOps continuous deployment
- Connecting FluxCD to a GitHub repository
- Automatically deploying applications from Git

**Architecture:**
- 1 control-plane node
- 2 worker nodes
- FluxCD controllers running in `flux-system` namespace
- Applications deployed from Git repository
- **NGINX** web server with custom ConfigMap
- **Traefik** ingress controller for traffic routing
- **KubeVIP** providing Virtual IP for LoadBalancer services

**What Gets Deployed:**
- NGINX on port 30080 (direct NodePort access) + Ingress at nginx.kind.local
- Traefik on port 80 (ingress controller with creative dashboard) via KubeVIP
- KubeVIP for LoadBalancer service support
- Automatic GitOps sync from GitHub repository

**Optional Setup:**
- Configure **mDNS** for automatic `*.kind.local` domain resolution
- See [README-kubevip-mdns.md](README-kubevip-mdns.md) for complete setup

---

## Prerequisites

Ensure the following tools are installed:

- **Docker** - Container runtime
- **kubectl** - Kubernetes CLI (v1.28+)
- **kind** - Kubernetes in Docker (v0.20+)
- **Git** - Version control

Verify installations:
```bash
docker --version
kubectl version --client
kind version
git --version
```

---

## Quick Start

For experienced users, run these commands in sequence:

```bash
# Create cluster
kind create cluster --config=kind-cluster.yaml

# Deploy FluxCD
kubectl apply -f https://github.com/fluxcd/flux2/releases/download/v2.2.3/install.yaml

# Wait for FluxCD to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=flux -n flux-system --timeout=5m

# Apply GitRepository and Kustomization
kubectl apply -f gitrepository.yaml
kubectl apply -f kustomization-sync.yaml

# Verify
kubectl get pods -A
curl http://localhost:30080
```

---

## Step-by-Step Setup

### 1. Create KinD Cluster

The `kind-cluster.yaml` configuration defines a three-node cluster with port mappings for accessing services.

**Create the cluster:**
```bash
kind create cluster --config=kind-cluster.yaml
```

**Verify cluster is running:**
```bash
kubectl cluster-info
kubectl get nodes
```

Expected output: 1 control-plane node and 2 worker nodes.

**Port Mappings:**
- `30080` → NGINX HTTP service
- `30081` → Alternative HTTP service
- `30090` → Traefik ingress controller
- `30443` → HTTPS service

---

### 2. Deploy FluxCD

FluxCD provides GitOps continuous delivery for Kubernetes.

**Option A: Using the deployment script**
```bash
./deploy-flux.sh
```

**Option B: Direct kubectl apply**
```bash
kubectl apply -f https://github.com/fluxcd/flux2/releases/download/v2.2.3/install.yaml
```

**Wait for FluxCD controllers to be ready:**
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=flux -n flux-system --timeout=5m
```

**Verify FluxCD installation:**
```bash
kubectl get pods -n flux-system
```

You should see these controllers running:
- `source-controller` - Handles Git repositories
- `kustomize-controller` - Applies Kustomize manifests
- `helm-controller` - Manages Helm releases
- `notification-controller` - Sends notifications

---

### 3. Connect to Git Repository

#### Option A: Public Repository (HTTPS - Recommended for Public Repos)

For public repositories, no authentication is required.

**Create GitRepository resource:**

The `gitrepository.yaml` file defines the connection to your Git repository:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: kind-lab
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/atwin140/Kind-lab.git
  ref:
    branch: Fluxcd-Lab
```

**Apply the configuration:**
```bash
kubectl apply -f gitrepository.yaml
```

**Create Kustomization resource:**

The `kustomization-sync.yaml` file tells FluxCD what to deploy from the repository:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: kind-lab-components
  namespace: flux-system
spec:
  interval: 5m
  path: ./components
  prune: true
  sourceRef:
    kind: GitRepository
    name: kind-lab
```

**Apply the configuration:**
```bash
kubectl apply -f kustomization-sync.yaml
```

**What this deploys:**

FluxCD will automatically deploy everything in the `./components` directory:
- **NGINX** - Web server with custom HTML (port 30080)
- **Traefik** - Ingress controller with creative dashboard (port 30090)
- **Ingress Rules** - Routes traffic from Traefik to NGINX

---

#### Option B: Private Repository (SSH Authentication)

Use this method for private repositories or when you prefer SSH.

**Step 1: Generate SSH Key Pair**
```bash
ssh-keygen -t ed25519 -C "flux@kind-lab" -f ./flux-deploy-key -N ""
```

This creates:
- `flux-deploy-key` (private key)
- `flux-deploy-key.pub` (public key)

**Step 2: Add Deploy Key to GitHub**

1. Display the public key:
   ```bash
   cat flux-deploy-key.pub
   ```

2. Add to GitHub:
   - Go to: https://github.com/atwin140/Kind-lab/settings/keys
   - Click **Add deploy key**
   - Paste the public key
   - Title: "FluxCD Deploy Key"
   - ✅ Check "Allow write access" (if FluxCD needs to commit)
   - Click **Add key**

**Step 3: Create Kubernetes Secret**

Generate GitHub's known_hosts and create the secret:
```bash
ssh-keyscan github.com > known_hosts

kubectl create secret generic flux-ssh-key \
  --from-file=identity=flux-deploy-key \
  --from-file=known_hosts=known_hosts \
  -n flux-system
```

**Step 4: Update GitRepository for SSH**

Modify `gitrepository.yaml` to use SSH:
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: kind-lab
  namespace: flux-system
spec:
  interval: 1m
  url: ssh://git@github.com/atwin140/Kind-lab.git
  ref:
    branch: Fluxcd-Lab
  secretRef:
    name: flux-ssh-key
```

Apply it:
```bash
kubectl apply -f gitrepository.yaml
```

Then create and apply the Kustomization resource as shown in Option A.

---

### 4. Verify Deployment

**Check FluxCD resources:**
```bash
# View GitRepository status
kubectl get gitrepository -n flux-system

# View Kustomization status
kubectl get kustomization -n flux-system

# Get detailed status
kubectl describe gitrepository kind-lab -n flux-system
kubectl describe kustomization kind-lab-components -n flux-system
```

**Check deployed applications:**
```bash
# View all pods
kubectl get pods -A

# View pods in nginx namespace (if deployed)
kubectl get pods -n nginx
```

---

## Testing Your Deployment

Once FluxCD has synced and deployed your applications, test the services:

**Test NGINX on port 30080 (direct NodePort):**
```bash
curl http://localhost:30080
```

Expected response: HTML page served by NGINX with "Hello from Oklahoma"

**Test Traefik on port 80 (via KubeVIP LoadBalancer):**
```bash
curl http://localhost:80
# or just
curl http://localhost
```

Expected response: Creative HTML page showing a plane being directed by Traefik air traffic control!

**Test with Ingress (kind.local domains):**

After setting up mDNS (see [README-kubevip-mdns.md](README-kubevip-mdns.md)):

```bash
# Access NGINX via Traefik ingress
curl http://nginx.kind.local

# All *.kind.local domains route through Traefik automatically!
```

**Manual testing without mDNS:**
```bash
# Add to /etc/hosts temporarily
echo "127.0.0.1 nginx.kind.local" | sudo tee -a /etc/hosts

# Test
curl http://nginx.kind.local
```

**For more details:**
- **Traefik ingress**: See [README-Traefik.md](README-Traefik.md)
- **KubeVIP & mDNS setup**: See [README-kubevip-mdns.md](README-kubevip-mdns.md)

---

## Monitoring and Troubleshooting

### Check All Pods

**View all pods across all namespaces:**
```bash
kubectl get pods -A
```

**View with additional details:**
```bash
kubectl get pods -A -o wide
```

**Watch pods in real-time:**
```bash
kubectl get pods -A -w
```

**Sort pods by status:**
```bash
kubectl get pods -A --sort-by=.status.phase
```

### Monitor FluxCD Controllers

**Check FluxCD pods:**
```bash
kubectl get pods -n flux-system
```

**View FluxCD pod logs:**
```bash
# List available pods
kubectl get pods -n flux-system

# View specific pod logs
kubectl logs -n flux-system <POD_NAME>

# Follow logs in real-time
kubectl logs -n flux-system <POD_NAME> -f
```

**View logs by controller:**
```bash
# Source controller (Git synchronization)
kubectl logs -n flux-system -l app=source-controller

# Kustomize controller (manifest application)
kubectl logs -n flux-system -l app=kustomize-controller

# Helm controller (Helm releases)
kubectl logs -n flux-system -l app=helm-controller
```

### Troubleshoot Issues

**Find non-running pods:**
```bash
kubectl get pods -A --field-selector=status.phase!=Running
```

**View cluster events:**
```bash
kubectl get events -A --sort-by='.lastTimestamp'
```

**Describe a pod for detailed information:**
```bash
kubectl describe pod <POD_NAME> -n <NAMESPACE>
```

**Check resource usage:**
```bash
kubectl top pods -A
kubectl top nodes
```

### Common Issues

**Issue: FluxCD not syncing**
```bash
# Check GitRepository status
kubectl describe gitrepository kind-lab -n flux-system

# Look for error messages in conditions
kubectl get gitrepository kind-lab -n flux-system -o yaml
```

**Issue: Kustomization failing**
```bash
# Check Kustomization status
kubectl describe kustomization kind-lab-components -n flux-system

# View kustomize-controller logs
kubectl logs -n flux-system -l app=kustomize-controller --tail=50
```

**Issue: Pods not starting**
```bash
# Check pod events
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# Check image pull status
kubectl get events -n <NAMESPACE> --sort-by='.lastTimestamp'
```

---

## Advanced Configuration

### Customizing FluxCD Sync Interval

Edit the GitRepository or Kustomization resources:

```yaml
spec:
  interval: 30s  # Sync every 30 seconds
  # or
  interval: 10m  # Sync every 10 minutes
```

### Enable GitOps Notifications

Configure notifications to Slack, Discord, or other platforms:
```bash
# Example: Configure Slack notification
kubectl create secret generic slack-url \
  --from-literal=address=https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  -n flux-system
```

### Cleanup and Reset

**Delete the cluster:**
```bash
kind delete cluster --name fluxcd-test
```

**Remove generated files:**
```bash
rm -f flux-deploy-key flux-deploy-key.pub known_hosts
```

---

## Useful Aliases

Save time with these kubectl aliases. Add them to your `~/.zshrc` or `~/.bashrc`:

```bash
# General kubectl
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kdel='kubectl delete'

# Namespace shortcuts
alias kf='kubectl -n flux-system'
alias kn='kubectl -n nginx'

# Common operations
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgpw='kubectl get pods -A -w'
alias klog='kubectl logs'
alias klogf='kubectl logs -f'

# FluxCD specific
alias flux-status='kubectl get gitrepository,kustomization -n flux-system'
alias flux-logs='kubectl logs -n flux-system -l app=source-controller'
```

**Apply aliases:**
```bash
source ~/.zshrc  # or ~/.bashrc
```

---

## Resources

- **FluxCD Documentation**: https://fluxcd.io/docs/
- **KinD Documentation**: https://kind.sigs.k8s.io/
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **GitHub Repository**: https://github.com/atwin140/Kind-lab

---

## Summary

This guide covered:
✅ Creating a multi-node KinD cluster  
✅ Installing FluxCD for GitOps  
✅ Connecting FluxCD to GitHub (HTTPS and SSH)  
✅ Deploying applications automatically from Git  
✅ Monitoring and troubleshooting Kubernetes resources  

Your cluster now automatically syncs with your Git repository, enabling true GitOps workflows where infrastructure and applications are managed through version control.
