#!/bin/sh

SSH_DIR="/root/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
FIX_NEEDED=0
LOG_BUFFER=""

# Fonction pour ajouter des messages au tampon
log_msg() {
    LEVEL="$1"
    TEXT="$2"
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    LOG_BUFFER="${LOG_BUFFER}[${TIMESTAMP}] [${LEVEL}] ${TEXT}\n"
}

check_and_fix() {
    log_msg "INFO" "Début du contrôle des accès SSH..."

    # 1. Vérification de l'existence
    if [ ! -d "$SSH_DIR" ]; then
        log_msg "WARN" "Le répertoire $SSH_DIR n'existe pas. Création."
        mkdir -p "$SSH_DIR"
        FIX_NEEDED=1
    fi

    if [ ! -f "$AUTH_KEYS" ]; then
        log_msg "WARN" "Le fichier $AUTH_KEYS n'existe pas. Création."
        touch "$AUTH_KEYS"
        FIX_NEEDED=1
    fi

    # 2. Vérification des propriétaires (UID/GID 0)
    SSH_DIR_OWNER=$(stat -c "%u:%g" "$SSH_DIR" 2>/dev/null)
    AUTH_KEYS_OWNER=$(stat -c "%u:%g" "$AUTH_KEYS" 2>/dev/null)

    if [ "$SSH_DIR_OWNER" != "0:0" ]; then
        log_msg "WARN" "Propriétaire de $SSH_DIR incorrect ($SSH_DIR_OWNER au lieu de 0:0)."
        FIX_NEEDED=1
    fi

    if [ "$AUTH_KEYS_OWNER" != "0:0" ]; then
        log_msg "WARN" "Propriétaire de $AUTH_KEYS incorrect ($AUTH_KEYS_OWNER au lieu de 0:0)."
        FIX_NEEDED=1
    fi

    # 3. Vérification des permissions (700 / 600)
    SSH_DIR_PERM=$(stat -c "%a" "$SSH_DIR" 2>/dev/null)
    AUTH_KEYS_PERM=$(stat -c "%a" "$AUTH_KEYS" 2>/dev/null)

    if [ "$SSH_DIR_PERM" != "700" ]; then
        log_msg "WARN" "Permissions de $SSH_DIR incorrectes ($SSH_DIR_PERM au lieu de 700)."
        FIX_NEEDED=1
    fi

    if [ "$AUTH_KEYS_PERM" != "600" ]; then
        log_msg "WARN" "Permissions de $AUTH_KEYS incorrectes ($AUTH_KEYS_PERM au lieu de 600)."
        FIX_NEEDED=1
    fi

    # 4. Application des correctifs si nécessaire
    if [ "$FIX_NEEDED" -eq 1 ]; then
        log_msg "INFO" "Anomalie(s) détectée(s). Application des correctifs..."

        chown -R root:root "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chmod 600 "$AUTH_KEYS"

        log_msg "INFO" "Correctifs appliqués avec succès."

        # Redémarrage du service SSH pour prise en compte
        if command -v service >/dev/null 2>&1; then
            service ssh restart >/dev/null 2>&1 && log_msg "INFO" "Service SSH redémarré (via service)."
        elif command -v systemctl >/dev/null 2>&1; then
            systemctl restart ssh >/dev/null 2>&1 && log_msg "INFO" "Service SSH redémarré (via systemctl)."
        fi
    else
        log_msg "INFO" "Aucun problème détecté sur les clés SSH. Configuration conforme."
    fi

    # Affichage atomique du tampon de log
    printf "%b" "$LOG_BUFFER"
}

check_and_fix
