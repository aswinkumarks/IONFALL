#!/usr/bin/env bash
# CI: internet play (decision 0005) needs the EOS credentials file, which is
# never committed. With the repository secrets in the environment, client
# builds get it and show online play; without them they're LAN-only.
set -euo pipefail
if [ -z "${EOS_CLIENT_SECRET:-}" ]; then echo "No EOS secrets: builds are LAN-only"; exit 0; fi
umask 077
printf '[eos]\nproduct_name="IONFALL"\nproduct_id="%s"\nsandbox_id="%s"\ndeployment_id="%s"\nclient_id="%s"\nclient_secret="%s"\n' \
	"$EOS_PRODUCT_ID" "$EOS_SANDBOX_ID" "$EOS_DEPLOYMENT_ID" "$EOS_CLIENT_ID" "$EOS_CLIENT_SECRET" > eos_credentials.cfg
echo "EOS credentials written: online play enabled in client builds"
