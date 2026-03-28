#!/bin/bash

while true; do
  INFOS=$(cat <<EOF

============================================
         $(date)
--------------------------------------------
         NETWORK PERFORMANCE REPORT       
--------------------------------------------

$(curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -W ignore - --simple)

--------------------------------------------
         GPU POWER & THERMAL REPORT
--------------------------------------------

$(nvidia-smi --query-gpu=index,name,power.draw,power.limit,power.default_limit,temperature.gpu --format=csv,noheader,nounits | awk -F', ' '{print "GPU " $1 " (" $2 "): " $3 "W / Limit " $4 "W (Default " $5 "W) - Temp: " $6 "°C"}')

============================================

EOF
)
    echo "$INFOS"
    # On attend 10 minutes
    sleep 600
done
