#!/bin/bash
# ------------------------------------------------------------------------------
# CLEANUP: Delete all Azure resources in the project resource group
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

echo "Subscription:"
az account show --query '{name:name,id:id,tenantId:tenantId,user:user.name}' -o table
echo
echo "Resources currently in ${RG}:"
az resource list --resource-group "$RG" \
  --query '[].{name:name,type:type,location:location}' -o table

if [ "$DELETE_REQUESTED" != "--delete" ]; then
    echo
    echo "Dry run only. To delete the entire resource group and all resources above, run:"
    echo "  bash $0 $CONFIG_FILE --delete"
    exit 0
fi

read -r -p "Type ${RG} to permanently delete the entire resource group: " CONFIRM
if [ "$CONFIRM" != "$RG" ]; then
    echo "Confirmation did not match. Nothing was deleted."
    exit 1
fi

echo "Deleting resource group ${RG}..."
az group delete --name "$RG" --yes --no-wait

echo "Waiting for Azure to confirm resource-group deletion..."
for attempt in $(seq 1 60); do
    if ! az group show --name "$RG" --output none 2>/dev/null; then
        echo "Resource group ${RG} has been deleted."
        break
    fi
    if [ "$attempt" -eq 60 ]; then
        echo "ERROR: Resource group still exists after the verification timeout." >&2
        exit 1
    fi
    sleep 10
done

if az resource list --resource-group "$RG" --output none 2>/dev/null; then
    echo "ERROR: Azure still reports resources in ${RG}." >&2
    exit 1
fi

echo "Cleanup verification complete: no resource group or project resources remain."
