# KubeVIP and mDNS Setup for kind.local

This guide configures KubeVIP to provide a Virtual IP (VIP) for your Kubernetes services and sets up mDNS (Multicast DNS) so that `*.kind.local` domains resolve automatically without manually editing `/etc/hosts`.

## Table of Contents

- [What is KubeVIP?](#what-is-kubevip)
- [What is mDNS?](#what-is-mdns)
- [Why Use Both Together?](#why-use-both-together)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step 1: Deploy KubeVIP](#step-1-deploy-kubevip)
- [Step 2: Configure mDNS](#step-2-configure-mdns)
- [Step 3: Configure Traefik with VIP](#step-3-configure-traefik-with-vip)
- [Step 4: Testing](#step-4-testing)
- [Troubleshooting](#troubleshooting)

---

## What is KubeVIP?

**KubeVIP** (Kubernetes Virtual IP) provides:
- **Virtual IP addresses** for Kubernetes services
- **Load balancing** for control plane and services
- **High availability** without external load balancers
- **ARP-based** VIP assignment (works great with KinD)

Think of it as giving your cluster a **stable, reachable IP address** that persists even if pods restart.

---

## What is mDNS?

**mDNS (Multicast DNS)** is a zero-configuration service that allows:
- Automatic hostname resolution on local networks
- No need to edit `/etc/hosts` manually
- `.local` domain support
- Used by Bonjour (macOS), Avahi (Linux)

With mDNS, `nginx.kind.local` automatically resolves to your KubeVIP address!

---

## Why Use Both Together?

```
┌─────────────────────────────────────────────────┐
│  You type: http://nginx.kind.local              │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │  mDNS Resolution   │
         │  *.kind.local      │
         │  → KubeVIP IP      │
         └────────┬───────────┘
                  │
                  ▼
         ┌────────────────────┐
         │   KubeVIP Service  │
         │   Virtual IP       │
         │   192.168.1.240    │
         └────────┬───────────┘
                  │
                  ▼
         ┌────────────────────┐
         │  Traefik Ingress   │
         │  Routes to backend │
         └────────┬───────────┘
                  │
                  ▼
         ┌────────────────────┐
         │   Your Service     │
         │   (nginx, api...)  │
         └────────────────────┘
```

**Benefits:**
- No manual `/etc/hosts` editing
- Professional local development environment
- Simulates production setup
- Easy to share with team (everyone gets same domains)

---

## Architecture

```
Host Machine (Mac/Linux)
├── mDNS Responder (Avahi/Bonjour)
│   └── Advertises: *.kind.local → 192.168.1.240
│
└── KinD Cluster
    ├── KubeVIP Pod (control-plane)
    │   └── Manages VIP: 192.168.1.240
    │
    ├── Traefik (LoadBalancer Service)
    │   └── Gets VIP from KubeVIP: 192.168.1.240
    │
    └── Backend Services (nginx, etc.)
        └── Accessed via: http://service.kind.local
```

---

## Prerequisites

- ✅ KinD cluster running
- ✅ kubectl configured
- ✅ macOS (Bonjour built-in) or Linux (Avahi)
- ✅ Network subnet for VIP (e.g., 192.168.1.240)

**Find your network subnet:**
```bash
# macOS
ipconfig getifaddr en0

# Linux
ip addr show | grep "inet " | grep -v 127.0.0.1
```

Choose an unused IP in your network's range for the VIP (e.g., if your machine is 192.168.1.100, use 192.168.1.240).

---

## Step 1: Deploy KubeVIP

### Option 1: Via FluxCD (GitOps)

The kubevip component is already in `components/kubevip/`. FluxCD will deploy it automatically.

**Check deployment:**
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip
```

### Option 2: Manual Deployment

```bash
kubectl apply -k components/kubevip/
```

### Verify KubeVIP

```bash
# Check DaemonSet
kubectl get daemonset -n kube-system kube-vip

# Check if VIP is assigned
kubectl get svc -A | grep LoadBalancer
```

You should see Traefik's LoadBalancer service with an EXTERNAL-IP (the VIP).

---

## Step 2: Configure mDNS

### On macOS (Bonjour - Built-in)

macOS has mDNS built-in via Bonjour. You just need to advertise the VIP.

**Create mDNS advertisement script:**

```bash
cat > /usr/local/bin/kind-mdns.sh << 'EOF'
#!/bin/bash
# Advertise kind.local via mDNS

VIP="192.168.1.240"  # Change to your KubeVIP address
DOMAIN="kind.local"

# Use dns-sd to advertise
dns-sd -P "KinD Cluster" _http._tcp local 80 $DOMAIN $VIP &
echo "Advertising $DOMAIN -> $VIP via mDNS"
echo "PID: $!"
EOF

chmod +x /usr/local/bin/kind-mdns.sh
```

**Run at startup (LaunchAgent):**

```bash
cat > ~/Library/LaunchAgents/com.kind.mdns.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.kind.mdns</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kind-mdns.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.kind.mdns.plist
```

### On Linux (Avahi)

**Install Avahi:**
```bash
# Ubuntu/Debian
sudo apt-get install avahi-daemon avahi-utils

# RHEL/Fedora
sudo dnf install avahi avahi-tools
```

**Create Avahi service file:**

```bash
sudo cat > /etc/avahi/services/kind.service << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>KinD Cluster</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <host-name>kind.local</host-name>
    <address>192.168.1.240</address>
  </service>
</service-group>
EOF
```

**Restart Avahi:**
```bash
sudo systemctl restart avahi-daemon
sudo systemctl enable avahi-daemon
```

### Verify mDNS

Test that kind.local resolves:

```bash
# Using ping (should resolve)
ping -c 1 kind.local

# Using DNS query
dns-sd -Q kind.local  # macOS
avahi-resolve -n kind.local  # Linux

# Using curl
curl -I http://nginx.kind.local
```

---

## Step 3: Configure Traefik with VIP

Update Traefik service to use LoadBalancer (already done if using our configuration):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: traefik
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.1.240  # Request specific VIP (optional)
  selector:
    app.kubernetes.io/name: traefik
  ports:
  - name: web
    port: 80
    targetPort: web
```

**Apply:**
```bash
kubectl apply -f components/traefik/service.yaml
```

**Verify VIP assignment:**
```bash
kubectl get svc -n traefik traefik
```

You should see `EXTERNAL-IP: 192.168.1.240`

---

## Step 4: Testing

### Test Direct VIP Access

```bash
# Access via VIP directly
curl http://192.168.1.240

# Should show Traefik welcome page
```

### Test mDNS Domain Resolution

```bash
# Resolve domain
ping -c 1 nginx.kind.local

# Access via domain
curl http://nginx.kind.local
```

### Test Multiple Services

```bash
# NGINX service
curl http://nginx.kind.local

# Add more Ingress resources for different services
curl http://api.kind.local
curl http://dashboard.kind.local
```

### Test from Browser

Open in your browser:
- http://nginx.kind.local
- http://kind.local (Traefik welcome)

**Everything should "just work" without editing /etc/hosts!**

---

## Troubleshooting

### Issue: kind.local doesn't resolve

**Check mDNS is running:**

macOS:
```bash
# Check if dns-sd is running
ps aux | grep dns-sd

# Manually test
dns-sd -Q kind.local
```

Linux:
```bash
# Check Avahi
sudo systemctl status avahi-daemon

# Query
avahi-resolve -n kind.local
```

**Try restarting mDNS:**
```bash
# macOS
launchctl unload ~/Library/LaunchAgents/com.kind.mdns.plist
launchctl load ~/Library/LaunchAgents/com.kind.mdns.plist

# Linux
sudo systemctl restart avahi-daemon
```

### Issue: Traefik not getting VIP

**Check KubeVIP is running:**
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip
```

**Check VIP is in correct subnet:**
```bash
# Your machine's IP
ipconfig getifaddr en0  # macOS
hostname -I  # Linux

# VIP should be in same subnet
```

**Verify LoadBalancer service:**
```bash
kubectl describe svc -n traefik traefik
```

### Issue: VIP already in use

**Check for conflicts:**
```bash
# Ping the VIP
ping -c 1 192.168.1.240

# Check ARP table
arp -a | grep 192.168.1.240
```

Choose a different IP if there's a conflict.

### Issue: Works with IP but not domain

This means mDNS isn't working. Check:
```bash
# Can you resolve other .local domains?
ping -c 1 somecomputer.local

# Try manual resolution
dns-sd -G v4 kind.local  # macOS
avahi-resolve -n kind.local  # Linux
```

### Issue: Certificate warnings in browser

For local development, you can:
1. Use HTTP (not HTTPS) for `*.kind.local`
2. Or generate self-signed certs with mkcert

**Using mkcert:**
```bash
# Install mkcert
brew install mkcert  # macOS
# or download from: https://github.com/FiloSottile/mkcert

# Install local CA
mkcert -install

# Generate cert for kind.local
mkcert "*.kind.local" kind.local

# Create Kubernetes secret
kubectl create secret tls kind-local-tls \
  --cert=_wildcard.kind.local.pem \
  --key=_wildcard.kind.local-key.pem \
  -n traefik
```

---

## Advanced: Wildcard DNS with dnsmasq

For even better local development, use dnsmasq to catch all `*.kind.local` queries:

**Install dnsmasq:**
```bash
# macOS
brew install dnsmasq

# Linux
sudo apt-get install dnsmasq
```

**Configure:**
```bash
# Add to dnsmasq config
echo "address=/kind.local/192.168.1.240" | sudo tee -a /etc/dnsmasq.conf
echo "address=/.kind.local/192.168.1.240" | sudo tee -a /etc/dnsmasq.conf

# Restart
sudo brew services restart dnsmasq  # macOS
sudo systemctl restart dnsmasq  # Linux
```

**Configure system DNS (macOS):**
```bash
sudo mkdir -p /etc/resolver
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/kind.local
```

---

## Summary

You now have:
✅ KubeVIP providing a stable Virtual IP for your cluster  
✅ mDNS automatically resolving `*.kind.local` domains  
✅ Traefik ingress accessible via clean domain names  
✅ Professional local development environment  
✅ No manual `/etc/hosts` editing needed  

**Example workflow:**
1. Create new service in Kubernetes
2. Create Ingress with `host: myservice.kind.local`
3. Access immediately at http://myservice.kind.local
4. No configuration needed - it just works!

---

## Resources

- **KubeVIP Documentation**: https://kube-vip.io/
- **Avahi Documentation**: https://www.avahi.org/
- **mDNS RFC**: https://datatracker.ietf.org/doc/html/rfc6762
- **mkcert**: https://github.com/FiloSottile/mkcert
