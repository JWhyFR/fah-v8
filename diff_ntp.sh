#!/bin/bash

# Si jamais ntpdate n'était pas dispo...
apt-get update 1>/dev/null 2>&1 && \
 apt-get install -y --no-install-recommends --no-install-suggests curl ntpsec-ntpdate 1>/dev/null 2>&1 

 
# Fonction d'affichage du décalage
function show_diff() {
  local label="$1"
  local diff="$2"
  if [ ${diff#-} -gt 10 ]; then
    echo "$label : décalage de ${diff}s par rapport à l'heure système."
  else
    echo "$label : synchronisé (écart de ${diff}s)."
  fi
}

echo "Vérification de l'heure système..."

# 1. Heure système locale
LOCAL_TS=$(date -u +%s)
echo "Heure système UTC : $LOCAL_TS"

# 2. Heure via API publique (worldclockapi.com)
API_TIME=$(curl -s  http://worldtimeapi.org/api/timezone/Etc/UTC | grep -oP '"unixtime":\K\d+')
if [ -n "$API_TIME" ]; then
  DIFF_API=$((LOCAL_TS - API_TIME))
  show_diff "API publique" "$DIFF_API"
else
  echo "API publique : Impossible de récupérer l'heure."
fi

# 3. Heure via NTP (time.google.com)
NTP_RAW=$(ntpdate -q time.google.com 2>/dev/null)
OFFSET=$(echo "$NTP_RAW" | awk '{print $4}' | head -n 1)
if [[ "$OFFSET" =~ ^[-+]?[0-9.]+$ ]]; then
  OFFSET_INT=$(printf "%.0f" "$OFFSET")
  show_diff "Serveur NTP" "$OFFSET_INT"
else
  echo "Serveur NTP : Impossible de récupérer l'heure."
fi
