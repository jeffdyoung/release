#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail


source "${SHARED_DIR}/packet-conf.sh" && scp "${SSHOPTS[@]}" "${SHARED_DIR}/nested_kubeconfig" "root@${IP}:nested_kubeconfig"

# shellcheck disable=SC2087
ssh "${SSHOPTS[@]}" "root@${IP}" bash - << 'EOF' |& sed -e 's/.*auths.*/*** PULL_SECRET ***/g'
set -x

API_SERVER=$(cat nested_kubeconfig | yq -r ".clusters[0].cluster.server" | sed 's|^http[s]*://||' | sed 's|:[0-9]*$||')
if [[ ! $API_SERVER =~ \[ && ! $API_SERVER =~ \] && ! $API_SERVER =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    API_SERVER=".${API_SERVER}"
fi
sed -i "1 s|$| $API_SERVER|" $HOME/squid.conf
cat $HOME/squid.conf

sudo setenforce 0
sudo podman stop -t 120 external-squid
sudo podman run -d --rm \
     --net host \
     --volume $HOME/squid.conf:/etc/squid/squid.conf \
     --name external-squid \
     --dns 127.0.0.1 \
     quay.io/openshifttest/squid-proxy:multiarch
EOF

CIRFILE=$SHARED_DIR/cir
PROXYPORT=8213
if [ -f $CIRFILE ] ; then
    PROXYPORT=$(jq -r ".extra | select( . != \"\") // {}" < $CIRFILE | jq ".ofcir_port_proxy // 8213" -r)
fi

echo "Adding proxy-url in kubeconfig"
sed -i "/- cluster/ a\    proxy-url: http://$IP:${PROXYPORT}/" "${SHARED_DIR}"/nested_kubeconfig
