#!/bin/bash
# ------------------------------------------------------------------------------
# PHASE 7: Safely remove the unused script-created VM after AVD validation
# ------------------------------------------------------------------------------
set -euo pipefail

DEFAULT_CONFIG="./avd_config.env"
CONFIG_FILE="${1:-$DEFAULT_CONFIG}"
DELETE_REQUESTED="${2:-}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file '${CONFIG_FILE}' not found." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${RG:?RG is required}"
: "${VM_NAME:?VM_NAME is required}"
: "${HOST_POOL_NAME:?HOST_POOL_NAME is required}"

HOST_POOL_ID=$(az desktopvirtualization hostpool show -g "$RG" -n "$HOST_POOL_NAME" --query id -o tsv)
VM_ID=$(az vm show -g "$RG" -n "$VM_NAME" --query id -o tsv 2>/dev/null || true)

if [ -z "$VM_ID" ]; then
    echo "VM '${VM_NAME}' does not exist. Nothing to remove."
    exit 0
fi

if az resource show --ids "$VM_ID" --query "tags.\"cm-resource-parent\"" -o tsv 2>/dev/null | grep -Fq "$HOST_POOL_ID"; then
    echo "ERROR: ${VM_NAME} is tagged as belonging to ${HOST_POOL_NAME}; refusing to remove it." >&2
    exit 1
fi

echo "Candidate VM: ${VM_NAME}"
az vm show -g "$RG" -n "$VM_NAME" -d \
  --query '{name:name,powerState:powerState,privateIp:privateIps,publicIp:publicIps,image:storageProfile.imageReference.sku}' -o table
echo "This VM is not a registered host-pool VM. Remove it only after a supported session host is available or if this utility VM is no longer needed."

if [ "$DELETE_REQUESTED" != "--delete" ]; then
    echo "Dry run only. Re-run with '--delete' after confirming AVD access works:"
    echo "  bash $0 $CONFIG_FILE --delete"
    exit 0
fi

read -r -p "Type ${VM_NAME} to permanently delete this VM and its dependent resources: " CONFIRM
if [ "$CONFIRM" != "$VM_NAME" ]; then
    echo "Confirmation did not match. Nothing was deleted."
    exit 1
fi

az vm delete --resource-group "$RG" --name "$VM_NAME" --yes
echo "Deleted VM ${VM_NAME}. Review its NIC and OS disk separately if they were retained."
