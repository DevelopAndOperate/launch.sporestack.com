#!/bin/sh

set -e

UUID=$(hostname | cut -d . -f 1)
DAYS=7
WALLET_COMMAND="walkingliberty send $(cat /root/service/bip32)"

sporestack topup --uuid $UUID --days $DAYS --wallet_command="$WALLET_COMMAND"

EXPIRES=$(sporestack node_info $UUID --attribute end_of_life)

RENEWAL=$(date -j -f %s $((EXPIRES - 3700)) +%Y%m%d%H%M)

echo 'sh /root/service/renew.sh' | at -t $RENEWAL
