#!/bin/bash
# ------------------------------------------------------------------------------
# PHASE 3: Configure NAT gateway and Entra ID permissions
# ------------------------------------------------------------------------------
set -euo pipefail

# 1. Source the configuration environment file dynamically
DEFAULT_CONFIG="./avd_config.env"
CONFIG_FILE="${1:-$DEFAULT_CONFIG}"

if [ -f "$CONFIG_FILE" ]; then
    echo "Loading configuration variables from: ${CONFIG_FILE}"
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file '${CONFIG_FILE}' not found." >&2
    exit 1
fi

: "${RG:?RG is required}"
: "${LOC:?LOC is required}"
: "${VNET:?VNET is required}"
: "${SUBNET:?SUBNET is required}"

echo "==> 1. Creating the NAT gateway if required..."
if ! az network nat gateway show --resource-group "$RG" --name nat-avd-outbound --output none 2>/dev/null; then
    az network public-ip create \
      --resource-group "$RG" \
      --name pip-nat-gateway \
      --sku Standard \
      --allocation-method Static \
      --location "$LOC" \
      --output none

    az network nat gateway create \
      --resource-group "$RG" \
      --name nat-avd-outbound \
      --public-ip-addresses pip-nat-gateway \
      --location "$LOC" \
      --output none
else
    echo "NAT gateway already exists; leaving it unchanged."
fi

echo "==> 2. Linking the NAT gateway to the compute subnet..."
az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --nat-gateway nat-avd-outbound \
  --output none

echo "==> 3. Retrieving your active authenticated identity details..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# FIXED: Extracting the strict Object ID from your current signed-in token session profile
# This completely bypasses the external guest account Graph search bugs
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
USER_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)

echo "------------------------------------------------------------"
echo "Resolved Principal Name: ${USER_UPN}"
echo "Graph Directory ID:      ${USER_OBJECT_ID}"
echo "Target Subscription:     ${SUBSCRIPTION_ID}"
echo "------------------------------------------------------------"

echo "==> 4. Ensuring 'Virtual Machine Administrator Login' is assigned..."
ROLE_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}"
ROLE_COUNT=$(az role assignment list \
  --assignee-object-id "$USER_OBJECT_ID" \
  --scope "$ROLE_SCOPE" \
  --query "[?roleDefinitionName=='Virtual Machine Administrator Login'] | length(@)" \
  -o tsv)

if [ "$ROLE_COUNT" = "0" ]; then
    az role assignment create \
      --role "Virtual Machine Administrator Login" \
      --assignee-object-id "$USER_OBJECT_ID" \
      --assignee-principal-type "User" \
      --scope "$ROLE_SCOPE" \
      --output none
else
    echo "Virtual Machine Administrator Login is already assigned; leaving it unchanged."
fi

echo "Phase 3 NAT and identity configuration complete!"
