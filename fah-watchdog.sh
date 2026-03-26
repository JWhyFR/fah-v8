#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="/var/log/fah-client/log.txt"
CHECK_INTERVAL=120

# Messages d'erreur à détecter
ERR_LOG="Lost connection to remote: Websocket not active"
ERR_LUFAH="Failed to connect to ws://127.0.0.1:7396"

# Action de relance
WORKING_DIR="/workspace"
EXEC_CMD="./fah-onstart.sh"
OUTPUT_LOG="fah-onstart.log"

# --- VARIABLES D'ENVIRONNEMENT ---
# pour forcer la relance dans le on-start, si jamais c'était en FALSE dans le template
export FAH_AUTOSTART=true
# ---------------------------------

LAST_MOD_TIME=0

echo "[$(date)] >>> Démarrage de la surveillance F@h"
echo "[$(date)] Cible de la surveillance : $LOG_FILE"
echo "[$(date)] Message à chercher dans la log : $ERR_LOG"
echo "[$(date)] Message à chercher dans LUFAH  : $ERR_LUFAH"
echo "[$(date)] Commande pour la relance : cd $WORKING_DIR && /bin/bash $EXEC_CMD"

# --- ATTENTE INITIALE ---
WAIT_TIME=$((CHECK_INTERVAL * 1))
echo "[$(date)] Attente de stabilisation ($WAIT_TIME secondes) avant le premier contrôle..."
sleep "$WAIT_TIME"
# ------------------------

while true; do
    if [ -f "$LOG_FILE" ]; then
        CURRENT_MOD_TIME=$(stat -c %Y "$LOG_FILE")

        # 1. On vérifie si le fichier est figé (pas de modif depuis le dernier tour)
        if [ "$CURRENT_MOD_TIME" -eq "$LAST_MOD_TIME" ]; then
            
            # 2. Tests d'erreurs (Log ET Lufah)
            tail -n 10 "$LOG_FILE" | grep -q "$ERR_LOG"
            LOG_STATUS=$?

            lufah 2>&1 | grep -q "$ERR_LUFAH"
            LUFAH_STATUS=$?

            # 3. Si un problème est détecté
            if [ $LOG_STATUS -eq 0 ] || [ $LUFAH_STATUS -eq 0 ]; then
                echo "[$(date)] ALERTE : Problème détecté !"
                
                [ $LOG_STATUS -eq 0 ] && echo "  -> Cause : Message d'erreur trouvé dans le log."
                [ $LUFAH_STATUS -eq 0 ] && echo "  -> Cause : Lufah ne parvient pas à se connecter."
                
                echo "[$(date)] Relance du service via $EXEC_CMD..."
                
                cd "$WORKING_DIR" || exit
                # Lancement avec /bin/bash pour garantir l'exécution
                nohup /bin/bash "$EXEC_CMD" >> "$OUTPUT_LOG" 2>&1 &
                
                # Petite pause pour laisser le temps au système de réagir
                sleep 15
                # Mise à jour du timestamp pour éviter une double relance immédiate
                CURRENT_MOD_TIME=$(stat -c %Y "$LOG_FILE")
            else
                # Message si le fichier est fixe mais sans erreur connue
                echo "[$(date)] Fichier figé mais aucune erreur détectée (Log/Lufah OK)."
            fi
        else
            # Message si tout va bien
            echo "[$(date)] OK : Le log évolue normalement ($LOG_FILE)."
        fi

        # Mise à jour de la référence pour le prochain tour
        LAST_MOD_TIME=$CURRENT_MOD_TIME
    else
        # Message si le fichier de log a disparu
        echo "[$(date)] Erreur : Fichier $LOG_FILE introuvable."
    fi

    # Attente avant le prochain cycle
    sleep "$CHECK_INTERVAL"
done
