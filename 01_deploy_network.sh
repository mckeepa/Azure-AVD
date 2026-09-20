#!/bin/bash
# -------------------------------------------------------------
# PHASE 1: Network & Security Gateway Setup - Australia East
# -------------------------------------------------------------
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
: "${LOC:?LOC is required}"
: "${VNET:?VNET is required}"
: "${SUBNET:?SUBNET is required}"
: "${VNET_ADDRESS_PREFIX:?VNET_ADDRESS_PREFIX is required in ${CONFIG_FILE}}"
: "${COMPUTE_SUBNET_PREFIX:?COMPUTE_SUBNET_PREFIX is required in ${CONFIG_FILE}}"
: "${BASTION_SUBNET_PREFIX:?BASTION_SUBNET_PREFIX is required in ${CONFIG_FILE}}"

echo "Creating the production Resource Group if required..."
az group create --name "$RG" --location "$LOC" --output none

if ! az network vnet show --resource-group "$RG" --name "$VNET" --output none 2>/dev/null; then
    echo "Creating Virtual Network (${VNET}) and host compute subnet..."
    az network vnet create \
      --resource-group "$RG" \
      --name "$VNET" \
      --address-prefix "$VNET_ADDRESS_PREFIX" \
      --subnet-name "$SUBNET" \
      --subnet-prefix "$COMPUTE_SUBNET_PREFIX" \
      --location "$LOC" \
      --output none
else
    echo "Virtual network already exists; leaving it unchanged."
fi

if ! az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET" --name AzureBastionSubnet --output none 2>/dev/null; then
    echo "Creating the required dedicated AzureBastionSubnet..."
    az network vnet subnet create \
      --resource-group "$RG" \
      --vnet-name "$VNET" \
      --name AzureBastionSubnet \
      --address-prefix "$BASTION_SUBNET_PREFIX" \
      --output none
else
    echo "AzureBastionSubnet already exists; leaving it unchanged."
fi

if ! az network public-ip show --resource-group "$RG" --name pip-bastion --output none 2>/dev/null; then
    echo "Allocating Standard Static Public IP for Bastion..."
    az network public-ip create \
      --resource-group "$RG" \
      --name pip-bastion \
      --sku Standard \
      --allocation-method Static \
      --location "$LOC" \
      --output none
else
    echo "Bastion public IP already exists; leaving it unchanged."
fi

if ! az network bastion show --resource-group "$RG" --name bastion-core --output none 2>/dev/null; then
    echo "Deploying Azure Bastion host (This takes roughly 5-10 minutes)..."
    az network bastion create \
      --resource-group "$RG" \
      --name bastion-core \
      --vnet-name "$VNET" \
      --public-ip-address pip-bastion \
      --sku Standard \
      --enable-tunneling true \
      --location "$LOC"
else
    echo "Bastion host already exists; leaving it unchanged."
fi

echo "Phase 1 Network infrastructure successfully deployed!"
