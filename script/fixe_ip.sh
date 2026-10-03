#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#   fixe_ip.sh — IP fixe PERMANENTE sur Ubuntu Server (Netplan)
#   Pose quelques questions, vérifie les valeurs, puis applique.
#   ────────────────────────────────────────────────────────────────
#   Outil signé : __KAT4NA_
# ════════════════════════════════════════════════════════════════════
#
#   Usage :  sudo bash fixe_ip.sh
#   Test sans rien modifier :  DRY_RUN=1 bash fixe_ip.sh

set -uo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; CYA='\033[0;36m'; BLD='\033[1m'; NC='\033[0m'

NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
BACKUP_DIR="/root/netplan-backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN="${DRY_RUN:-0}"
PY="${PYTHON:-python3}"

ok()   { echo -e "  ${GRN}✔${NC} $1"; }
info() { echo -e "  ${CYA}→${NC} $1"; }
warn() { echo -e "  ${YEL}⚠${NC} $1"; }
die()  { echo -e "  ${RED}✘ $1${NC}"; exit 1; }

# ── Validations (Python : stdlib, déjà présent sur Ubuntu Server) ──
valid_ipv4() {
    "$PY" -c "import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])" "$1" 2>/dev/null
}
valid_prefix() {
    [[ "$1" =~ ^[0-9]{1,2}$ ]] && [ "$1" -ge 8 ] && [ "$1" -le 30 ]
}
in_subnet() {  # in_subnet IP PREFIX GATEWAY
    "$PY" -c "import ipaddress,sys
net = ipaddress.ip_network(f'{sys.argv[1]}/{sys.argv[2]}', strict=False)
sys.exit(0 if ipaddress.ip_address(sys.argv[3]) in net else 1)" "$1" "$2" "$3" 2>/dev/null
}
valid_dns_list() {
    "$PY" -c "import ipaddress,sys
[ipaddress.ip_address(x.strip()) for x in sys.argv[1].split(',') if x.strip()]
" "$1" 2>/dev/null
}

# ask "Question" "défaut" "fonction_de_validation"  → REPLY_VAL
ask() {
    local question="$1" default="${2:-}" validator="${3:-true}" input
    while true; do
        if [ -n "$default" ]; then
            read -r -p "  $question [$default] : " input || die "Entrée interrompue."
            input="${input:-$default}"
        else
            read -r -p "  $question : " input || die "Entrée interrompue."
        fi
        if [ -n "$input" ] && $validator "$input"; then
            REPLY_VAL="$input"
            return 0
        fi
        echo -e "    ${YEL}→ Valeur invalide, réessaie.${NC}"
    done
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BLD}Configuration d'une IP fixe (permanente) — Netplan${NC}"
echo ""

if [ "$DRY_RUN" != "1" ]; then
    [ "$(id -u)" -eq 0 ] || die "Lance ce script en root : sudo bash $0"
    command -v netplan >/dev/null 2>&1 || die "netplan introuvable (Ubuntu Server requis)"
fi
command -v "$PY" >/dev/null 2>&1 || die "python3 introuvable"

# ── Valeurs actuelles (utilisées comme défauts) ────────────────────
DEF_IFACE=$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')
DEF_GW=$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')
DEF_CIDR=$(ip -4 -o addr show dev "${DEF_IFACE:-lo}" 2>/dev/null | awk '{print $4; exit}')
DEF_IP="${DEF_CIDR%/*}"
DEF_PREFIX="${DEF_CIDR#*/}"
[ "$DEF_PREFIX" = "$DEF_CIDR" ] && DEF_PREFIX="24"

echo -e "${BLD}Interfaces réseau :${NC}"
ip -o link show | awk -F': ' '$2 !~ /^lo$/ {print "    - " $2}' | sed 's/@.*//'
echo ""

# ── Questions ──────────────────────────────────────────────────────
ask "Interface réseau" "${DEF_IFACE:-ens18}" true
IFACE="$REPLY_VAL"

ask "IP fixe (ex. 10.2.3.237)" "$DEF_IP" valid_ipv4
IP="$REPLY_VAL"

ask "Masque en CIDR (ex. 24 pour 255.255.255.0, 22 pour 255.255.252.0)" "$DEF_PREFIX" valid_prefix
PREFIX="$REPLY_VAL"

ask "Passerelle (Gatwa)" "$DEF_GW" valid_ipv4
GW="$REPLY_VAL"

ask "DNS, séparés par une virgule" "8.8.8.8,1.1.1.1" valid_dns_list
DNS="$REPLY_VAL"

# ── Vérifications de cohérence ─────────────────────────────────────
echo ""
echo -e "${BLD}Vérifications :${NC}"

if [ "$IP" = "$GW" ]; then
    die "L'IP fixe ne peut pas être la passerelle elle-même."
fi
if ! in_subnet "$IP" "$PREFIX" "$GW"; then
    die "La passerelle $GW n'est pas dans le réseau $IP/$PREFIX. Vérifie l'IP et le masque."
fi
ok "Passerelle $GW dans le réseau $IP/$PREFIX"

if ping -c 1 -W 1 "$IP" >/dev/null 2>&1; then
    warn "L'IP $IP répond déjà sur le réseau : un autre appareil l'utilise (conflit)."
    read -r -p "  Continuer quand même ? [o/N] : " yn
    [[ "$yn" =~ ^[oOyY]$ ]] || die "Annulé."
else
    ok "L'IP $IP ne répond pas (libre)"
fi

# ── YAML généré ────────────────────────────────────────────────────
DNS_YAML=$("$PY" -c "import sys; print(', '.join(x.strip() for x in sys.argv[1].split(',') if x.strip()))" "$DNS")
YAML=$(cat <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${IP}/${PREFIX}
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${DNS_YAML}]
EOF
)

echo ""
echo -e "${BLD}Configuration qui sera écrite dans ${NETPLAN_FILE} :${NC}"
echo "$YAML" | sed 's/^/    /'
echo ""

if [ "$DRY_RUN" = "1" ]; then
    echo -e "${YEL}Mode test (DRY_RUN=1) : rien n'a été modifié.${NC}"
    exit 0
fi

read -r -p "  Appliquer cette configuration ? [o/N] : " yn
[[ "$yn" =~ ^[oOyY]$ ]] || { echo "Annulé, rien n'a été modifié."; exit 0; }

# ── Application ────────────────────────────────────────────────────
echo ""
echo -e "${BLD}▶ Sauvegarde et écriture${NC}"
mkdir -p "$BACKUP_DIR"
for f in /etc/netplan/*.yaml; do
    [ -e "$f" ] || continue
    mv "$f" "$BACKUP_DIR/"
    ok "Ancien fichier mis de côté : $f"
done

# Désactive la réécriture réseau par cloud-init (sinon l'IP revient au reboot)
if [ -d /etc/cloud ]; then
    touch /etc/cloud/cloud-init.disabled
    echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    ok "cloud-init ne touchera plus au réseau"
fi

echo "$YAML" > "$NETPLAN_FILE"
chmod 600 "$NETPLAN_FILE"
ok "Fichier écrit : $NETPLAN_FILE (600)"

echo -e "\n${BLD}▶ Vérification de la syntaxe${NC}"
if ! netplan generate 2>/tmp/fixe_ip_err.log; then
    cat /tmp/fixe_ip_err.log
    rm -f "$NETPLAN_FILE"
    mv "$BACKUP_DIR"/*.yaml /etc/netplan/ 2>/dev/null
    die "Configuration refusée par netplan. Ancienne config restaurée."
fi
ok "Syntaxe valide"

echo -e "\n${BLD}▶ Application${NC}"
if [ -n "${SSH_CLIENT:-}" ]; then
    warn "Tu es connecté en SSH. Si l'IP change, ta connexion va couper."
    warn "Reconnecte-toi ensuite sur : ssh $(whoami)@$IP"
fi
read -r -p "  Lancer 'netplan apply' maintenant ? [o/N] : " yn
if [[ ! "$yn" =~ ^[oOyY]$ ]]; then
    info "Pas appliqué. Ça prendra effet au prochain redémarrage, ou lance : sudo netplan apply"
    exit 0
fi
netplan apply
sleep 2

echo -e "\n${BLD}▶ Résultat${NC}"
if ip -4 -o addr show dev "$IFACE" | grep -q " ${IP}/"; then
    ok "IP $IP/$PREFIX active sur $IFACE"
else
    warn "L'IP $IP n'apparaît pas sur $IFACE : vérifie avec 'ip -4 addr'"
fi
if ip route show default | grep -q "via ${GW}"; then
    ok "Passerelle $GW active"
else
    warn "Passerelle non vérifiée : vérifie avec 'ip route'"
fi

echo ""
echo -e "${GRN}${BLD}IP fixe configurée.${NC}"
echo "  Ancienne config sauvegardée dans : $BACKUP_DIR"
echo "  Pour revenir en arrière : sudo cp $BACKUP_DIR/*.yaml /etc/netplan/ && sudo netplan apply"
echo ""
