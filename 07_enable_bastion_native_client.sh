#!/bin/bash
# ------------------------------------------------------------------------------
# PHASE 8: Enable Azure Bastion native-client tunneling
# ------------------------------------------------------------------------------
set -euo pipefail

DEFAULT_CONFIG="./avd_config.env"
CONFIG_FILE="${1:-$DEFAULT_CONFIG}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file '${CONFIG_FILE}' not found." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${RG:?RG is required}"

echo "Current Bastion configuration:"
az network bastion show \
  --resource-group "$RG" \
  --name bastion-core \
  --query '{name:name,sku:sku.name,provisioningState:provisioningState,enableTunneling:enableTunneling}' \
  -o table

echo "Enabling native-client tunneling on bastion-core..."
az network bastion update \
  --resource-group "$RG" \
  --name bastion-core \
  --enable-tunneling true \
  --output none

echo "Updated Bastion configuration:"
az network bastion show \
  --resource-group "$RG" \
  --name bastion-core \
  --query '{name:name,sku:sku.name,provisioningState:provisioningState,enableTunneling:enableTunneling}' \
  -o table
