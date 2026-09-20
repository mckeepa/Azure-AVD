#!/bin/bash
# ------------------------------------------------------------------------------
# PHASE 5: Verify AVD session-host health, entitlement, and VM ownership
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
: "${HOST_POOL_NAME:?HOST_POOL_NAME is required}"
: "${APP_GROUP_NAME:?APP_GROUP_NAME is required}"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
API_VERSION="${AVD_API_VERSION:-2022-02-10-preview}"
SESSION_HOST_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.DesktopVirtualization/hostPools/${HOST_POOL_NAME}/sessionHosts?api-version=${API_VERSION}"

echo "==> Azure account"
az account show --query '{subscription:name,subscriptionId:id,tenantId:tenantId,user:user.name}' -o table

echo
echo "==> AVD control plane"
az desktopvirtualization hostpool show -g "$RG" -n "$HOST_POOL_NAME" \
  --query '{name:name,type:hostPoolType,loadBalancer:loadBalancerType,preferredAppGroup:preferredAppGroupType}' -o table
az desktopvirtualization applicationgroup show -g "$RG" -n "$APP_GROUP_NAME" \
  --query '{name:name,type:applicationGroupType,hostPool:hostPoolArmPath,workspace:workspaceArmPath}' -o table

echo
echo "==> Registered session hosts"
az rest --method get --url "$SESSION_HOST_URL" \
  --query 'value[].{name:name,status:properties.status,allowNewSession:properties.allowNewSession,agentVersion:properties.agentVersion,healthChecks:properties.sessionHostHealthCheckResults}' \
  -o table

echo
echo "==> Resource ownership"
az vm list -g "$RG" -d \
  --query "[].{name:name,powerState:powerState,privateIp:privateIps,publicIp:publicIps,provisioningState:provisioningState}" \
  -o table
echo
echo "VMs tagged with cm-resource-parent belong to a portal-managed AVD host-pool deployment:"
az resource list -g "$RG" \
  --resource-type Microsoft.Compute/virtualMachines \
  --query "[?tags.\"cm-resource-parent\" != null].{name:name,parent:tags.\"cm-resource-parent\"}" \
  -o table

echo
echo "==> App-group role assignments"
APP_GROUP_ID=$(az desktopvirtualization applicationgroup show -g "$RG" -n "$APP_GROUP_NAME" --query id -o tsv)
az role assignment list --scope "$APP_GROUP_ID" \
  --query "[].{principal:principalName,role:roleDefinitionName,type:principalType}" \
  -o table

echo
echo "Interpretation: the session host must be Available and allowNewSession=True."
