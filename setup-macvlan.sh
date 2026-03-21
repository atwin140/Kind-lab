#!/usr/bin/env bash
# setup-macvlan.sh
#
# STEP 1 (before cluster creation):
#   Creates a macvlan Podman network ("kind-macvlan") bridged to the host
#   physical NIC so Kind node containers can reach the 10.0.1.x LAN.
#
# STEP 2 (after cluster creation):
#   Attaches every Kind node container to "kind-macvlan", giving each node
#   a second NIC (eth1) in the 10.0.1.x subnet.  Multus uses this interface
#   as the master for pod secondary networks.
#
# Usage:
#   # Create the Podman macvlan network first:
#   sudo ./setup-macvlan.sh create-network
#
#   # Then create the cluster (rootful Podman required for macvlan):
#   sudo KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --config kind-cluster.yaml
#
#   # Then attach nodes to the macvlan network:
#   sudo ./setup-macvlan.sh attach-nodes
#
# Requirements:
#   - RHEL 10 host (rootful Podman – macvlan requires CAP_NET_ADMIN / root)
#   - podman >= 4.0  (podman network connect support)
#   - kind
#   - SELinux note: if containers fail to start, check 'ausearch -m avc -ts recent'
#     A common fix: setsebool -P container_manage_cgroup on

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
# Host physical NIC that faces the 10.0.1.0/24 network.
# Auto-detected from the default route; override with PARENT_IFACE env var.
PARENT_IFACE="${PARENT_IFACE:-$(ip route | awk '/^default/ {print $5; exit}')}"
SUBNET="10.0.1.0/24"
GATEWAY="10.0.1.1"
# IP range Podman uses when *it* auto-assigns IPs to containers on this network.
# Keep this outside the kube-vip / Multus allocation range (10.0.1.200-250).
DOCKER_IP_RANGE="10.0.1.128/26"   # .128 – .191 reserved for Kind nodes
NETWORK_NAME="kind-macvlan"
CLUSTER_NAME="${CLUSTER_NAME:-fluxcd-test}"
# ──────────────────────────────────────────────────────────────────────────────

cmd="${1:-help}"

create_network() {
  echo "==> Parent interface : ${PARENT_IFACE}"
  echo "    Subnet           : ${SUBNET}"
  echo "    Podman IP range  : ${DOCKER_IP_RANGE}"
  echo "    Network name     : ${NETWORK_NAME}"

  if podman network inspect "${NETWORK_NAME}" &>/dev/null; then
    echo "==> Network '${NETWORK_NAME}' already exists – skipping creation."
    return
  fi

  podman network create \
    --driver macvlan \
    --subnet="${SUBNET}" \
    --gateway="${GATEWAY}" \
    --ip-range="${DOCKER_IP_RANGE}" \
    -o parent="${PARENT_IFACE}" \
    "${NETWORK_NAME}"

  echo "==> Network '${NETWORK_NAME}' created."
  echo ""
  echo "Next: sudo KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --config kind-cluster.yaml"
  echo "Then: sudo ./setup-macvlan.sh attach-nodes"
}

attach_nodes() {
  echo "==> Attaching Kind nodes to '${NETWORK_NAME}' ..."
  # Podman uses the container name/ID; Kind labels containers with the cluster name.
  # Works the same for rootful Podman (which Kind requires on RHEL).
  nodes=$(podman ps --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" --format '{{.Names}}')
  if [[ -z "${nodes}" ]]; then
    echo "ERROR: No Kind containers found for cluster '${CLUSTER_NAME}'."
    echo "       Are you running as root / with sudo?"
    echo "       Set CLUSTER_NAME env var if your cluster has a different name."
    exit 1
  fi

  for node in ${nodes}; do
    # Check if already connected by inspecting the container's networks.
    if podman inspect "${node}" \
        --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' \
        | grep -qw "${NETWORK_NAME}"; then
      echo "    ${node} already connected – skipping."
    else
      podman network connect "${NETWORK_NAME}" "${node}"
      echo "    ${node} connected."
    fi
  done

  echo ""
  echo "==> Done.  Each Kind node now has a secondary NIC (eth1) in ${SUBNET}."
  echo "    Multus NetworkAttachmentDefinition uses master: eth1."
  echo ""
  echo "    TIP: to reach Multus IPs FROM this RHEL host itself,"
  echo "    add a macvlan shim (macvlan cannot talk to its own parent by default):"
  echo ""
  echo "      ip link add macvlan-shim link ${PARENT_IFACE} type macvlan mode bridge"
  echo "      ip addr add 10.0.1.1/32 dev macvlan-shim"
  echo "      ip link set macvlan-shim up"
  echo "      ip route add ${DOCKER_IP_RANGE} dev macvlan-shim"
  echo ""
  echo "    If SELinux blocks container networking:"
  echo "      sudo setsebool -P container_manage_cgroup on"
  echo "      sudo ausearch -m avc -ts recent | audit2allow -M mymultus"
  echo "      sudo semodule -i mymultus.pp"
}

help() {
  grep '^#' "$0" | head -20
  echo ""
  echo "Commands:"
  echo "  create-network   Create the macvlan Docker network"
  echo "  attach-nodes     Connect Kind node containers to the network"
}

case "${cmd}" in
  create-network) create_network ;;
  attach-nodes)   attach_nodes ;;
  *)              help ;;
esac
