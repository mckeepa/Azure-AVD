#!/bin/bash
# ------------------------------------------------------------------------------
# Open an Azure Bastion tunnel from Linux.
# The tunnel is the transport; the RDP client performs VM authentication.
# ------------------------------------------------------------------------------
set -euo pipefail

DEFAULT_CONFIG="./avd_config.env"
CONFIG_FILE="${1:-$DEFAULT_CONFIG}"
TARGET_VM_NAME="${2:-AVD-Bastion-0}"
LOCAL_PORT="${3:-13389}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file '${CONFIG_FILE}' not found." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${RG:?RG is required}"

if ! command -v az >/dev/null 2>&1; then
    echo "ERROR: Azure CLI is required." >&2
    exit 1
fi

if ! command -v xfreerdp >/dev/null 2>&1 && ! command -v xfreerdp3 >/dev/null 2>&1; then
    echo "ERROR: Install FreeRDP first: sudo apt-get install -y freerdp2-x11" >&2
    exit 1
fi

BASTION_TUNNELING=$(az network bastion show \
  --resource-group "$RG" \
  --name bastion-core \
  --query enableTunneling \
  --output tsv)

if [ "$BASTION_TUNNELING" != "true" ]; then
    echo "ERROR: Bastion native tunneling is disabled." >&2
    echo "Run: bash 07_enable_bastion_native_client.sh ${CONFIG_FILE}" >&2
    exit 1
fi

VM_ID=$(az vm show \
  --resource-group "$RG" \
  --name "$TARGET_VM_NAME" \
  --query id \
  --output tsv)

echo "Opening Bastion tunnel to ${TARGET_VM_NAME}."
echo "Connect from another terminal with an RDP client to 127.0.0.1:${LOCAL_PORT}."
echo "Press Ctrl+C here to close the tunnel."

exec az network bastion tunnel \
  --resource-group "$RG" \
  --name bastion-core \
  --target-resource-id "$VM_ID" \
  --resource-port 3389 \
  --port "$LOCAL_PORT"
