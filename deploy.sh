#!/bin/bash

# === CONFIGURATION DES IMAGES ===
IMG_DIR="./images"
VMANAGE_IMG="$IMG_DIR/vmanage.qcow2"
VBOND_IMG="$IMG_DIR/vbond.qcow2"
VSMART_IMG="$IMG_DIR/vsmart.qcow2"
VEDGE1_IMG="$IMG_DIR/vedge1.qcow2"
VEDGE3_IMG="$IMG_DIR/vedge3.qcow2"
CSR_IMG="$IMG_DIR/csr1000v.qcow2"
TEST_IMG="$IMG_DIR/testhost.qcow2"

# === ÉTAPE 1 : CRÉATION DES BRIDGES ===
echo "[+] Nettoyage des anciens bridges..."
for br in br-mgmt br-ctrl br-wan; do
    nmcli con delete "$br" &>/dev/null
    ip link delete "$br" type bridge &>/dev/null
    ip link delete "tap-$br" &>/dev/null
    ip link delete "veth-$br" &>/dev/null
    sleep 1
    echo "[-] $br supprimé"
done

nmcli con add type bridge con-name br-mgmt ifname br-mgmt
nmcli con modify br-mgmt ipv4.addresses 172.16.1.254/24 ipv4.method manual
nmcli con up br-mgmt

nmcli con add type bridge con-name br-ctrl ifname br-ctrl
nmcli con modify br-ctrl ipv4.addresses 10.10.1.254/24 ipv4.method manual
nmcli con up br-ctrl

nmcli con add type bridge con-name br-wan ifname br-wan
nmcli con modify br-wan ipv4.addresses 172.19.0.254/16 ipv4.method manual
nmcli con up br-wan

# === ROUTING ===
echo "[+] Activation IP Forwarding"
sysctl -w net.ipv4.ip_forward=1

# === FONCTION DE LANCEMENT QEMU ===
launch_vm() {
    local name=$1
    local img=$2
    local ram=$3
    local mac0=$4
    local mac1=$5
    local mac2=$6
    local br0=$7
    local br1=$8
    local br2=$9
    local port=${10:-0} # port série optionnel

    echo "[+] Lancement $name..."
    if [ "$port" -ne 0 ]; then
        SERIAL="-serial telnet:localhost:$port,server,nowait"
    else
        SERIAL=""
    fi

    xterm -e qemu-kvm -name "$name" \
        -hda "$img" \
        -m "$ram" -smp 2 -enable-kvm -nographic \
        -netdev bridge,id=net0,br=$br0,helper=/usr/libexec/qemu-bridge-helper \
        -device virtio-net-pci,netdev=net0,mac=$mac0 \
        -netdev bridge,id=net1,br=$br1,helper=/usr/libexec/qemu-bridge-helper \
        -device virtio-net-pci,netdev=net1,mac=$mac1 \
        -netdev bridge,id=net2,br=$br2,helper=/usr/libexec/qemu-bridge-helper \
        -device virtio-net-pci,netdev=net2,mac=$mac2 $SERIAL &
    sleep 3
}

# === LANCEMENT DES VMs ===
launch_vm "vManage" $VMANAGE_IMG 16384 \
    52:54:00:aa:00:01 52:54:00:aa:00:02 52:54:00:aa:00:03 \
    br-mgmt br-ctrl br-wan 6001

launch_vm "vBond" $VBOND_IMG 4096 \
    52:54:00:aa:01:01 52:54:00:aa:01:02 52:54:00:aa:01:03 \
    br-mgmt br-ctrl br-wan 6002

launch_vm "vSmart" $VSMART_IMG 4096 \
    52:54:00:aa:02:01 52:54:00:aa:02:02 52:54:00:aa:02:03 \
    br-mgmt br-ctrl br-wan 6003

launch_vm "vEdge1" $VEDGE1_IMG 4096 \
    52:54:00:aa:03:01 52:54:00:aa:03:02 52:54:00:aa:03:03 \
    br-mgmt br-ctrl br-wan 6004

launch_vm "vEdge3" $VEDGE3_IMG 4096 \
    52:54:00:aa:04:01 52:54:00:aa:04:02 52:54:00:aa:04:03 \
    br-mgmt br-ctrl br-wan 6005

launch_vm "CSR1000v" $CSR_IMG 2048 \
    52:54:00:aa:05:01 52:54:00:aa:05:02 52:54:00:aa:05:03 \
    br-mgmt br-ctrl br-wan 6006

launch_vm "TestHost" $TEST_IMG 512 \
    52:54:00:aa:06:01 52:54:00:aa:06:02 52:54:00:aa:06:03 \
    br-mgmt br-ctrl br-wan 6007

# === CONFIGURATION AUTOMATIQUE VIA EXPECT ===
echo "[+] Attente du démarrage des VMs..."
sleep 60

echo "[+] Configuration automatique des composants SD-WAN via expect..."
expect config/config_vmanage.expect
expect config/config_vbond.expect
expect config/config_vsmart.expect
expect config/config_vedge1.expect
expect config/config_vedge3.expect

# === INSTALLATION DES CERTIFICATS (optionnel à intégrer) ===
# bash certs/openssl_cert_gen.sh
# expect config/install_cert.expect

# === FIN ===
echo "[+] Toutes les VMs sont lancées et configurées."
echo "[*] Accès console via telnet localhost 6001-6007."
echo "[*] Configuration des certificats à suivre dans l'étape suivante."
