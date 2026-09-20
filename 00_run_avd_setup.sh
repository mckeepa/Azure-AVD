#!/bin/bash
# ------------------------------------------------------------------------------
# End-to-end AVD setup runner
#
# Usage:
#   bash 00_run_avd_setup.sh ./avd_config.env
#   bash 00_run_avd_setup.sh ./avd_config.env --continue
#   bash 00_run_avd_setup.sh ./avd_config.env --check-only
# ------------------------------------------------------------------------------
set -euo pipefail

DEFAULT_CONFIG="./avd_config.env"
CONFIG_FILE="${1:-$DEFAULT_CONFIG}"
MODE="${2:-}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file '${CONFIG_FILE}' not found." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${RG:?RG is required}"
: "${HOST_POOL_NAME:?HOST_POOL_NAME is required}"

run_if_needed() {
    local script="$1"
    shift
    bash "$script" "$CONFIG_FILE" "$@"
}

available_host_count() {
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    az rest --method get \
      --url "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${RG}/providers/Microsoft.DesktopVirtualization/hostPools/${HOST_POOL_NAME}/sessionHosts?api-version=2022-02-10-preview" \
      --query 'length(value[?properties.status==`Available` && properties.allowNewSession==`true`])' \
      -o tsv
}

check_only() {
    bash 04_verify_avd_state.sh "$CONFIG_FILE"
    echo
    echo "A usable host must report Status=Available and AllowNewSession=True."
}

if [ "$MODE" = "--check-only" ]; then
    check_only
    exit 0
fi

echo "==> Running scripted infrastructure steps"
run_if_needed 01_deploy_network.sh
run_if_needed 02_deploy_avd_compute.sh
run_if_needed 03_assign_permissions.sh
run_if_needed 07_enable_bastion_native_client.sh
run_if_needed 05_assign_avd_user_access.sh

echo
echo "==> Checking for a registered, usable AVD session host"
HOST_COUNT=$(available_host_count)
if [ "$HOST_COUNT" -eq 0 ] && [ "$MODE" != "--continue" ]; then
    cat <<'INSTRUCTIONS'

PAUSED: Manual session-host step required

The installed Azure CLI does not provide the supported portal-style command for adding
an Azure VM to an AVD host pool. Complete this step in Azure Portal:

1. Open Host pools > hp-avd-main > Session hosts > Add.
2. Select Azure virtual machine in Australia East.
3. Select a current Windows 11 Enterprise multi-session image.
4. Select Microsoft Entra ID for the join type.
5. Select vnet-avd-core and snet-avd-compute.
6. Set public inbound ports to None/No.
7. Do not select AzureBastionSubnet.
8. Finish deployment and wait for the host to appear as Available.

Then resume this runner from Linux:

  bash 00_run_avd_setup.sh ./avd_config.env --continue

The runner will not continue until a registered host is Available and accepts new sessions.
INSTRUCTIONS
    exit 10
fi

if [ "$MODE" = "--continue" ]; then
    echo "==> Waiting for a usable session host"
    for attempt in $(seq 1 60); do
        HOST_COUNT=$(available_host_count)
        if [ "$HOST_COUNT" -gt 0 ]; then
            break
        fi
        echo "No Available host yet; checking again in 30 seconds (${attempt}/60)..."
        sleep 30
    done
    if [ "$HOST_COUNT" -eq 0 ]; then
        echo "ERROR: No Available session host was detected." >&2
        check_only
        exit 1
    fi
fi

echo "==> Final verification"
check_only
echo
echo "==> Connect through the AVD web client:"
echo "https://client.wvd.microsoft.com/arm/webclient"
echo "Workspace: ${WORKSPACE_NAME}"
