#!/bin/bash

# Syntaxe : ./sys-monitor.sh [INTERVALLE_SECONDES] [LOG_FILE]
# Exemple 1 : ./sys-monitor.sh (1 passe, pas de log)
# Exemple 2 : ./sys-monitor.sh /root/sys-monitor.log (1 passe + log)
# Exemple 3 : ./sys-monitor.sh 10 /root/sys-monitor.log (boucle 10s + log)

if [[ "$1" =~ ^[0-9]+$ ]]; then
    INTERVAL=$1
    LOG_FILE=$2
else
    INTERVAL=0
    LOG_FILE=$1
fi

run_monitoring() {
  # 2 sauts de ligne pour aérer les blocs successifs dans le fichier de log
  echo -e "\n\n"
	echo "================================================================================"
  echo "  SYSTEM & GPU MONITORING - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "================================================================================"

	echo -e "\n=== CPU INFO ==="
	echo "CPU Model          : $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'N/A')"
	echo "CPU ID             : $(awk -F': ' '/vendor_id/ {v=$2} /cpu family/ {f=$2} /model/ && !/model name/ {m=$2} /stepping/ {s=$2} END {printf "%s Family %s Model %s Stepping %s", v, f, m, s}' /proc/cpuinfo 2>/dev/null)"
	echo "CPUs               : $(nproc)"
	grep "cpu MHz" /proc/cpuinfo | awk '{sum+=$4; count++} END {printf "CPU Freq           : %.0f MHz (avg on %d cores)\n", sum/count, count}'	
	
	echo -e "\n=== MEMORY USAGE ==="
	# 1. Essai cgroup v2
	if [ -f /sys/fs/cgroup/memory.current ]; then
		u=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0)
		l_raw=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
		[ "$l_raw" = "max" ] && l=0 || l=$l_raw
	# 2. Essai cgroup v1
	elif [ -f /sys/fs/cgroup/memory/memory.usage_in_bytes ]; then
		u=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo 0)
		l=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 0)
	# 3. Fallback (pas de cgroup lisible)
	else
		u=0
		l=0
	fi
	# Affichage Container RAM
	if [ "$l" -gt 1000000000000000 ] || [ "$l" -eq 0 ]; then
		echo "Container RAM      : Unlimited (Host RAM)"
	else
		echo | awk -v u=$u -v l=$l '{
			used=u/1073741824; total=l/1073741824; free=total-used;
			printf "Container RAM      : %.2f GiB used | %.2f GiB free | %.2f GiB total (%.1f%%)\n", used, free, total, (u/l)*100
		}'
	fi
	# Affichage Host RAM
	free -b | awk '/Mem:/ {
		used=$3/1073741824; free=$7/1073741824; total=$2/1073741824;
		printf "Host RAM           : %.2f GiB used | %.2f GiB free | %.2f GiB total (%.1f%%)\n", used, free, total, ($3/$2)*100
	}'

	echo -e "\n=== OS INFO ==="
	echo "OS Distribution    : $(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -s)"
	echo "Kernel Version     : $(uname -r)"
	
  echo -e "\n=== DRIVER & CUDA INFO ==="
  echo "Host Driver        : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)"
  echo "Max CUDA Support   : $(nvidia-smi | grep -oP 'CUDA Version: \K[0-9.]+' | head -n 1)"
  echo "CUDA Runtime       : $(dpkg -l | grep -E "cuda-cudart-[0-9]+" | awk '{print $2 " (v" $3 ")"}' || echo "No dpkg cuda-cudart package found")"

  echo -e "\n=== GPU INFO  ==="
  nvidia-smi --query-gpu=name,memory.total,temperature.gpu,utilization.gpu,utilization.memory,power.draw,power.limit,power.default_limit,power.max_limit,compute_cap --format=csv,noheader | awk -F', ' '{
      draw=$6; sub(/ W/,"",draw);
      limit=$7; sub(/ W/,"",limit);
      def=$8; sub(/ W/,"",def);
      max=$9; sub(/ W/,"",max);
      capped = (limit < def) ? " (power capped)" : "";
      print "GPU Model          : " $1;
  print "Compute Capability : " $10;
      print "Total VRAM         : " $2;
      print "VRAM Utilization   : " $5;
      print "GPU Temp           : " $3 " °C";
      print "GPU Utilization    : " $4;
      print "Power Draw         : " $6;
      print "Power Limit        : " $7 capped;
      print "Max VBIOS Limit    : " $9;
  }'

	echo -e "\n=== FAH PROCESSES ==="
	ps -eo pid,user,%mem,rss,args | grep -E "(^|/)(fah-client|FahCore_[a-z0-9]+)($|[[:space:]])" | grep -vE "(grep|SCREEN)" | awk '
	BEGIN { printf "%-8s %-10s %-6s %-12s %s\n", "PID", "USER", "%MEM", "RSS", "COMMAND" }
	{
		mib = $4 / 1024;
		if (mib >= 1024) {
			mem_str = sprintf("%.2f GiB", mib / 1024);
		} else {
			mem_str = sprintf("%.1f MiB", mib);
		}
		printf "%-8s %-10s %-6s %-12s %s\n", $1, $2, $3 "%", mem_str, $5
	}
	END { if (NR==0) print "No FAH process running" }'


  echo -e "\n=== SUBDIRECTORIES IN /ROOT ==="
  du -h --max-depth=1 /root 2>/dev/null | grep -v "^.*/root$" | sort -f -k2

  echo -e "\n=== FILES IN /ROOT ROOT ==="
  find /root -maxdepth 1 -type f -exec du -ch {} + 2>/dev/null | grep total$ || echo "No individual files"
}

execute() {
    if [ -n "$LOG_FILE" ]; then
        run_monitoring | tee -a "$LOG_FILE"
    else
        run_monitoring
    fi
}

# Boucle principale
if [ "$INTERVAL" -gt 0 ]; then
    while true; do
        clear
        execute
        [ -n "$LOG_FILE" ] && echo "--> Output appended to $LOG_FILE"
        echo -e "\n[Refreshing every ${INTERVAL}s - Press Ctrl+C to stop]"
        sleep "$INTERVAL"
    done
else
    execute
    [ -n "$LOG_FILE" ] && echo -e "\n--> Output appended to $LOG_FILE"
fi
