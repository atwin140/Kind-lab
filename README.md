# Kind-lab2 FLUXCD
A place to learn about kube
# Getting started with Fluxcd in a kind cluster
- build new kind cluster
- Deploy Fluxcd 
- Connect to Repo and deploy new web page


# Build Kind cluster

```bash
kind create cluster --config=kind-cluster.yaml
```

# Deploy FluxCD

```bash
./deploy-flux.sh
```

This script will:
- Download the FluxCD v2.2.3 installation manifests
- Apply them to your cluster
- Wait for all Flux controllers to be ready

or you can just run 
```
kubectl apply -n flux-system -f https://github.com/fluxcd/flux2/releases/download/v2.2.3/install.yaml
```

# Connect FluxCD to Git Repository

## Option 1: Public Repository (HTTPS - No Keys Required)

For public repositories, you can use HTTPS without any authentication.

### 1. Create GitRepository Resource

Create a file called `gitrepository.yaml`:

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

Apply it:
```bash
kubectl apply -f gitrepository.yaml
```

### 2. Create Kustomization to Deploy Components

Create a file called `kustomization-sync.yaml`:

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

Apply it:
```bash
kubectl apply -f kustomization-sync.yaml
```

### 3. Verify

Check that Flux is syncing with your repository:

```bash
# Check GitRepository status
kubectl get gitrepository -n flux-system

# Check Kustomization status
kubectl get kustomization -n flux-system

# Get detailed status with conditions
kubectl describe gitrepository kind-lab -n flux-system
kubectl describe kustomization kind-lab-components -n flux-system
```

## Monitoring Pod Status

### Check all pods across all namespaces:
```bash
# View all pods in all namespaces
kubectl get pods -A

# View all pods with more details (node, IP, etc.)
kubectl get pods -A -o wide

# Watch pods in real-time (updates automatically)
kubectl get pods -A -w

# View pods with their status sorted
kubectl get pods -A --sort-by=.status.phase
```

### Check Flux system pods specifically:
```bash
# Check Flux pods
kubectl get pods -n flux-system

# Get detailed info about Flux pods
kubectl get pods -n flux-system -o wide

# Check pod logs (replace POD_NAME with actual pod name)
kubectl logs -n flux-system <POD_NAME>

# Follow logs in real-time
kubectl logs -n flux-system <POD_NAME> -f

# Check logs for all source-controller pods
kubectl logs -n flux-system -l app=source-controller

# Check logs for all kustomize-controller pods
kubectl logs -n flux-system -l app=kustomize-controller
```

### Check pods in specific namespaces:
```bash
# View pods in default namespace
kubectl get pods

# View pods in a specific namespace
kubectl get pods -n <namespace>

# Check pod resource usage
kubectl top pods -A
```

### Troubleshooting pods:
```bash
# Describe a specific pod for detailed info and events
kubectl describe pod <POD_NAME> -n <namespace>

# Get pod events across all namespaces
kubectl get events -A --sort-by='.lastTimestamp'

# Check for failed/pending pods
kubectl get pods -A --field-selector=status.phase!=Running
```

---

## Option 2: Private Repository or SSH (Requires Keys)

If your repository is private or you prefer SSH authentication:

### 1. Create SSH Keys

Generate an SSH key pair for FluxCD to authenticate with GitHub:

```bash
ssh-keygen -t ed25519 -C "flux@kind-lab" -f ./flux-deploy-key -N ""
```

This creates:
- `flux-deploy-key` (private key)
- `flux-deploy-key.pub` (public key)

### 2. Add Deploy Key to GitHub

1. Copy the public key:
   ```bash
   cat flux-deploy-key.pub
   ```

2. Go to your GitHub repository: https://github.com/atwin140/Kind-lab
3. Navigate to **Settings** → **Deploy keys** → **Add deploy key**
4. Paste the public key and give it a title (e.g., "FluxCD Deploy Key")
5. Check "Allow write access" if Flux needs to commit back to the repo
6. Click **Add key**

### 3. Create Kubernetes Secrets

Get GitHub's SSH host keys and create the secret:

```bash
ssh-keyscan github.com > known_hosts

kubectl create secret generic flux-ssh-key \
  --from-file=identity=flux-deploy-key \
  --from-file=known_hosts=known_hosts \
  -n flux-system
```

### 4. Create GitRepository Resource

Create a file called `gitrepository.yaml`:

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

Then follow steps 2-3 from Option 1 to create the Kustomization and verify.


# Check the status

I like to use alias to save on typing
```
alias k=kubectl
alias kf="kubectl -n flux-system"
alias kn="kubectl -n nginx"
```
now lets check ths status 