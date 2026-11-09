#!/bin/bash
## MODIF : Refont du script pour ne faire le speedtest que toutes les 12h , et le test GPU toutes les 30 mn
## MODIF : Remplacement du speedtest.py par le speedtest ookla
## MODIF : Remplacement du speedtest ookla  par librespeed

# Recupération de la dernière version de librespeed
LS_URL=$(curl -s "https://api.github.com/repos/librespeed/speedtest-cli/releases/latest" | \
      awk -F'"' '/browser_download_url/ && /linux/ && /amd64/ {print $4; exit}')
curl -sL "$LS_URL" | tar -xzf - --wildcards "librespeed-cli*" --transform='s|.*/||' --transform='s|_.*||'

# Initialisation : 24 pour forcer le premier test réseau au démarrage
freq=24
count=$freq
while true; do
  # 1. Préparation de l'entête et du bloc GPU (Toujours présent)
  REPORT="
============================================
    $(date)
--------------------------------------------
    GPU POWER & THERMAL REPORT (30m)
--------------------------------------------

$(nvidia-smi --query-gpu=index,name,power.draw,power.limit,power.default_limit,temperature.gpu --format=csv,noheader,nounits | awk -F', ' '{print "GPU " $1 " (" $2 "): " $3 "W / Limit " $4 "W (Default " $5 "W) - Temp: " $6 "°C"}')
"

  # 2. Ajout du bloc Réseau seulement toutes les 12 heures (toutes les 24 boucles de 30 min)
  if [ $count -ge $freq ]; then
      TEMP_OUTPUT=$(./librespeed-cli --csv --duration 5 --server $(./librespeed-cli --list 2>/dev/null | grep -i "United States\|USA" | shuf -n 1 | awk -F':' '{print $1}') 2>/dev/null | grep -v '^$' | tail -n 1 | sed -E 's/("([^"]*)")?,/\2|/g')
      NETWORK_DATA=$(echo "$TEMP_OUTPUT" | awk -F'|' '{
          print "Serveur: " $2 "\nPing: " $4 " ms\nDownload: " $6 " Mbit/s\nUpload: " $7 " Mbit/s"
      }')      
           
    # On insère le bloc réseau AU-DESSUS du bloc GPU pour garder une hiérarchie propre
    REPORT="$REPORT
--------------------------------------------
    NETWORK PERFORMANCE REPORT ($((freq / 2))h)
--------------------------------------------

$NETWORK_DATA
"
    count=0
  fi

  # 3. Fermeture et affichage
  echo "
$REPORT
============================================

"	

  # Incrément et pause
  count=$((count + 1))
  sleep 1800
done
