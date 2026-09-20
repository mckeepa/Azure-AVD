#!/bin/bash
# ------------------------------------------------------------------------------
# PHASE 6: Grant the signed-in user access to the AVD desktop application group
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
: "${APP_GROUP_NAME:?APP_GROUP_NAME is required}"

USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
USER_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
APP_GROUP_ID=$(az desktopvirtualization applicationgroup show \
  --resource-group "$RG" --name "$APP_GROUP_NAME" --query id -o tsv)

echo "User:       ${USER_UPN}"
echo "Object ID:  ${USER_OBJECT_ID}"
echo "App group:  ${APP_GROUP_ID}"

if az role assignment list --assignee-object-id "$USER_OBJECT_ID" --scope "$APP_GROUP_ID" \
  --query "[?roleDefinitionName=='Desktop Virtualization User'] | length(@)" -o tsv | grep -q '^1$'; then
    echo "Desktop Virtualization User role is already assigned."
    exit 0
fi

echo "Assigning Desktop Virtualization User at application-group scope..."
az role assignment create \
  --assignee-object-id "$USER_OBJECT_ID" \
  --assignee-principal-type User \
  --role "Desktop Virtualization User" \
  --scope "$APP_GROUP_ID" \
  --output none

echo "Role assignment completed for ${USER_UPN}."
