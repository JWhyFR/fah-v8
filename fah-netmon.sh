#!/bin/bash

# --- DETECTION AUTOMATIQUE ROBUSTE DE L'INTERFACE PRINCIPALE ---
get_default_interface() {
    local iface=""
    if command -v ip >/dev/null 2>&1; then
        iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n 1)
    fi
    if [ -z "$iface" ] && command -v route >/dev/null 2>&1; then
        iface=$(route -n 2>/dev/null | awk '/^0\.0\.0\.0/ {print $8}' | head -n 1)
    fi
    if [ -z "$iface" ] && [ -f /proc/net/dev ]; then
        iface=$(awk -F: '/:/ {print $1}' /proc/net/dev | tr -d ' ' | grep -v '^lo$' | head -n 1)
    fi
    echo "${iface:-eth0}"
}

INTERFACE=$(get_default_interface)
IFACE_PATH="/sys/class/net/$INTERFACE/statistics"

if [ ! -d "$IFACE_PATH" ]; then
    echo "Erreur : Impossible d'acceder aux statistiques pour l'interface '$INTERFACE'."
    exit 1
fi

# --- VALEURS PAR DEFAUT (EN MO) ---
MAX_MB_5M=200
MAX_MB_20M=300
MAX_MB_60M=400

# --- PARSING DES ARGUMENTS NOMMES ---
for arg in "$@"; do
    case "$arg" in
        5M=*)  MAX_MB_5M="${arg#*=}" ;;
        20M=*) MAX_MB_20M="${arg#*=}" ;;
        60M=*) MAX_MB_60M="${arg#*=}" ;;
        *)     echo "[ATTENTION] Option inconnue ignoree : $arg" ;;
    esac
done

# Conversion en octets
THRESH_5M=$((MAX_MB_5M * 1024 * 1024))
THRESH_20M=$((MAX_MB_20M * 1024 * 1024))
THRESH_60M=$((MAX_MB_60M * 1024 * 1024))

# --- VARIABLES D'ETAT POUR COOLDOWN ---
alert_active_dl_5m=0; alert_active_ul_5m=0
alert_active_dl_20m=0; alert_active_ul_20m=0
alert_active_dl_60m=0; alert_active_ul_60m=0

# Compteur de minutes pour l'affichage périodique (60 min)
tick_counter=0

# --- AFFICHAGE DE DEMARRAGE ---
echo "========================================"
echo "Lancement du script : $(date +'%Y-%m-%d %H:%M:%S')"
echo "Interface reseau detectee : $INTERFACE"
echo "Seuils d'alerte megoctets configures :"
echo " - 5 minutes  : ${MAX_MB_5M} Mo"
echo " - 20 minutes : ${MAX_MB_20M} Mo"
echo " - 60 minutes : ${MAX_MB_60M} Mo"
echo "Surveillance en cours..."
echo "========================================"

declare -a hist_rx
declare -a hist_tx

hist_rx[0]=$(cat "$IFACE_PATH/rx_bytes")
hist_tx[0]=$(cat "$IFACE_PATH/tx_bytes")

check_alert() {
    local minutes=$1
    local threshold=$2
    local label=$3
    local var_dl_name="alert_active_dl_${minutes}m"
    local var_ul_name="alert_active_ul_${minutes}m"
    
    if [ ${#hist_rx[@]} -gt "$minutes" ]; then
        local current_rx=${hist_rx[0]}
        local current_tx=${hist_tx[0]}
        local past_rx=${hist_rx[$minutes]}
        local past_tx=${hist_tx[$minutes]}

        local dl_bytes=$((current_rx - past_rx))
        local ul_bytes=$((current_tx - past_tx))

        # --- GESTION DOWNLOAD ---
        if [ "$dl_bytes" -gt "$threshold" ]; then
            if [ "${!var_dl_name}" -eq 0 ]; then
                local dl_mo=$((dl_bytes / 1024 / 1024))
                echo "[$(date +'%H:%M:%S')] [ALERTE] DOWNLOAD ($INTERFACE) : $dl_mo Mo telecharges en $minutes min ! (Seuil: ${label}) | Cooldown actif : alerte suspendue pour au moins $minutes min."
                eval "$var_dl_name=1"
            fi
        else
            eval "$var_dl_name=0"
        fi

        # --- GESTION UPLOAD ---
        if [ "$ul_bytes" -gt "$threshold" ]; then
            if [ "${!var_ul_name}" -eq 0 ]; then
                local ul_mo=$((ul_bytes / 1024 / 1024))
                echo "[$(date +'%H:%M:%S')] [ALERTE] UPLOAD ($INTERFACE) : $ul_mo Mo envoyes en $minutes min ! (Seuil: ${label}) | Cooldown actif : alerte suspendue pour au moins $minutes min."
                eval "$var_ul_name=1"
            fi
        else
            eval "$var_ul_name=0"
        fi
    fi
}

print_periodic_summary() {
    echo "----------------------------------------"
    echo "[$(date +'%H:%M:%S')] [RAPPORT HORAIRE] Consommation mesuree sur $INTERFACE :"
    
    for minutes in 5 20 60; do
        if [ ${#hist_rx[@]} -gt "$minutes" ]; then
            local dl_bytes=$((hist_rx[0] - hist_rx[$minutes]))
            local ul_bytes=$((hist_tx[0] - hist_tx[$minutes]))
            local dl_mo=$((dl_bytes / 1024 / 1024))
            local ul_mo=$((ul_bytes / 1024 / 1024))
            echo " - ${minutes} min  : DL = ${dl_mo} Mo | UL = ${ul_mo} Mo"
        else
            echo " - ${minutes} min  : Donnees insuffisantes (${#hist_rx[@]} min d'historique)"
        fi
    done
    echo "----------------------------------------"
}

while true; do
    sleep 60
    
    current_rx=$(cat "$IFACE_PATH/rx_bytes")
    current_tx=$(cat "$IFACE_PATH/tx_bytes")
    
    hist_rx=("$current_rx" "${hist_rx[@]}")
    hist_rx=("${hist_rx[@]:0:61}")
    
    hist_tx=("$current_tx" "${hist_tx[@]}")
    hist_tx=("${hist_tx[@]:0:61}")

    check_alert 5 "$THRESH_5M" "${MAX_MB_5M}Mo"
    check_alert 20 "$THRESH_20M" "${MAX_MB_20M}Mo"
    check_alert 60 "$THRESH_60M" "${MAX_MB_60M}Mo"

    ((tick_counter++))
    if [ "$tick_counter" -ge 60 ]; then
        print_periodic_summary
        tick_counter=0
    fi
done
