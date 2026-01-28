#!/bin/bash

# Chemin parent où se trouvent les sous-répertoires aléatoires
TARGET_DIR="/root/work"

# Boucle infinie
while true; do
    # -type f : cherche des fichiers
    # -name "viewerFrame*.json" : cherche le motif exact
    # -size +1M : strictement supérieur à 1 Mo
    # -delete : supprime directement les fichiers trouvés
    find "$TARGET_DIR" -type f -name "viewerFrame*.json" -size +1M -delete

    # Attente de 30 secondes avant la prochaine exécution
    sleep 30
done
