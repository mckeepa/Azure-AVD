#!/bin/bash
# ------------------------------------------------------------------------------
# PHASE 2: Reusable AVD Host Pool & Compute Script (Parameter Input & Fixed Args)
# ------------------------------------------------------------------------------
set -euo pipefail

# 1. Determine configuration file location based on parameter or default path
DEFAULT_CONFIG="./avd_config.env"
CONFIG_FILE="${1:-$DEFAULT_CONFIG}"

# 2. Check if the determined configuration file exists
if [ -f "$CONFIG_FILE" ]; then
    echo "Loading configuration variables from: ${CONFIG_FILE}"
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file '${CONFIG_FILE}' not found." >&2
    echo "Usage: $0 [path_to_env_file]" >&2
    echo "If no path is specified, it defaults to: ${DEFAULT_CONFIG}" >&2
    exit 1
fi

# 3. Basic safety validation to verify critical variables loaded successfully
: "${RG:?Missing RG in ${CONFIG_FILE}}"
: "${LOC:?Missing LOC in ${CONFIG_FILE}}"
: "${VNET:?Missing VNET in ${CONFIG_FILE}}"
: "${SUBNET:?Missing SUBNET in ${CONFIG_FILE}}"
: "${VM_NAME:?Missing VM_NAME in ${CONFIG_FILE}}"
: "${VM_SIZE:?Missing VM_SIZE in ${CONFIG_FILE}}"
: "${ADMIN_USER:?Missing ADMIN_USER in ${CONFIG_FILE}}"
: "${HOST_POOL_NAME:?Missing HOST_POOL_NAME in ${CONFIG_FILE}}"
: "${APP_GROUP_NAME:?Missing APP_GROUP_NAME in ${CONFIG_FILE}}"
: "${WORKSPACE_NAME:?Missing WORKSPACE_NAME in ${CONFIG_FILE}}"

ADMIN_PASS=""
trap 'unset ADMIN_PASS' EXIT

request_admin_password() {
    local password_confirmation
    while true; do
        read -r -s -p "Enter the local administrator password for ${VM_NAME}: " ADMIN_PASS
        printf '\n'
        read -r -s -p "Confirm the local administrator password: " password_confirmation
        printf '\n'
        if [ -z "$ADMIN_PASS" ]; then
            echo "ERROR: Password cannot be empty." >&2
        elif [ "$ADMIN_PASS" != "$password_confirmation" ]; then
            echo "ERROR: Passwords do not match." >&2
        else
            unset password_confirmation
            return 0
        fi
    done
}

if ! az vm show --resource-group "$RG" --name "$VM_NAME" --output none 2>/dev/null; then
    request_admin_password
else
    echo "VM already exists; no administrator password is requested."
fi

if [ -z "$ADMIN_USER" ]; then
    echo "ERROR: ADMIN_USER cannot be empty." >&2
    exit 1
fi

echo "==> 1. Registering required Azure desktop virtualization providers..."
az provider register --namespace Microsoft.DesktopVirtualization

echo "==> 2. Creating the AVD Host Pool (${HOST_POOL_NAME}) if required..."
if ! az desktopvirtualization hostpool show --resource-group "$RG" --name "$HOST_POOL_NAME" --output none 2>/dev/null; then
    az desktopvirtualization hostpool create \
      --resource-group "$RG" \
      --name "$HOST_POOL_NAME" \
      --location "$LOC" \
      --host-pool-type "Pooled" \
      --load-balancer-type "BreadthFirst" \
      --preferred-app-group-type "Desktop"
else
    echo "Host pool already exists; leaving it unchanged."
fi

echo "==> 3. Creating the AVD Desktop Application Group (${APP_GROUP_NAME}) if required..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if ! az desktopvirtualization applicationgroup show --resource-group "$RG" --name "$APP_GROUP_NAME" --output none 2>/dev/null; then
    az desktopvirtualization applicationgroup create \
      --resource-group "$RG" \
      --name "$APP_GROUP_NAME" \
      --location "$LOC" \
      --application-group-type "Desktop" \
      --host-pool-arm-path "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.DesktopVirtualization/hostpools/${HOST_POOL_NAME}"
else
    echo "Application group already exists; leaving it unchanged."
fi

echo "==> 4. Creating the AVD Workspace (${WORKSPACE_NAME}) if required..."
# FIXED: Changed --application-groups to --application-group-references to match official extension schema
if ! az desktopvirtualization workspace show --resource-group "$RG" --name "$WORKSPACE_NAME" --output none 2>/dev/null; then
    az desktopvirtualization workspace create \
      --resource-group "$RG" \
      --name "$WORKSPACE_NAME" \
      --location "$LOC" \
      --application-group-references "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.DesktopVirtualization/applicationgroups/${APP_GROUP_NAME}"
else
    echo "Workspace already exists; leaving it unchanged."
fi

echo "==> 5. Deploying the utility Windows VM (${VM_NAME}) if required..."
if ! az vm show --resource-group "$RG" --name "$VM_NAME" --output none 2>/dev/null; then
    az vm create \
      --resource-group "$RG" \
      --name "$VM_NAME" \
      --location "$LOC" \
      --vnet-name "$VNET" \
      --subnet "$SUBNET" \
      --image "MicrosoftWindowsDesktop:windows-11:win11-23h2-avd:latest" \
      --admin-username "$ADMIN_USER" \
      --admin-password "$ADMIN_PASS" \
      --public-ip-address "" \
      --nsg "" \
      --size "$VM_SIZE"
else
    echo "VM already exists; leaving it unchanged."
fi
unset ADMIN_PASS

echo "==> 6. Injecting the AADLoginForWindows extension (Enables Entra ID Native Join)..."
az vm extension set \
  --publisher "Microsoft.Azure.ActiveDirectory" \
  --name "AADLoginForWindows" \
  --resource-group "$RG" \
  --vm-name "$VM_NAME" \
  --output none

echo "==> 7. Configuring VM metadata to enable automatic OS updates..."
az vm update \
  --resource-group "$RG" \
  --name "$VM_NAME" \
  --set osProfile.windowsConfiguration.enableAutomaticUpdates=true \
  --output none

echo "Phase 2 control-plane and utility-VM deployment complete."
echo "The VM is not an AVD session host until it is registered through the host-pool workflow."
