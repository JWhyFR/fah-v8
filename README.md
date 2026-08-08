#  [FR] Scripts d'automatisation FAH-v8

Cet ensemble de scripts shell a pour but de faciliter le déploiement, la gestion, la surveillance et l'optimisation du client Folding@home (v8), particulièrement dans des environnements conteneurisés exploitant des configurations mono- ou multi-GPU (comme l'infrastructure Vast.ai).

Ces scripts sont conçus pour s'exécuter automatiquement lors de la création de votre instance Vast.ai. 
Pour apprendre à les intégrer dans un template Vast.ai et configurer correctement le champ "On-start script / bash commands [...]", consultez le [Guide GPU Cloud disponible sur le site de l'équipe Alliance Francophone - Folding@home](https://www.alliancefrancophone.org/dossiers/gpu-cloud) et plus particulièrement la page dédiée à [la configuration d'un template et des scripts de démarrage](https://www.alliancefrancophone.org/dossiers/gpu-cloud-02-03).

La plupart de ces scripts peuvent être exécutés en arrière-plan à l'aide de la commande `nohup` suivie d'une esperluette (`&`). Leurs flux de sortie peuvent être redirigés vers des fichiers de log dédiés, dont le contenu peut lui-même être redirigé vers la sortie standard du conteneur (`> /proc/1/fd/1`) pour être directement consultable depuis l'interface Vast.ai via le bouton "LOG" de l'instance.

De plus, la plupart des dépendances nécessaires (comme `curl`, `bzip2`, `pipx`, `screen`, `libexpat1`, `jq`, etc.) sont gérées automatiquement par les scripts d'initialisation ou définies dans le `Dockerfile` inclus.

💡 **Remarque** : Seul le script d'initialisation (`fah-onstart-cuda.sh` ou -au pire- sa version précédente) est strictement indispensable au bon démarrage du client Folding@home sur Vast.ai, l'utilisation des autres scripts de surveillance et de nettoyage restant optionnelle.

## Description des scripts

### 1. [fah-onstart-cuda.sh](fah-onstart-cuda.sh) _(recommandé)_
- **Rôle** : C'est le script d'initialisation principal. Il installe les runtimes nécessaires (CUDA, Lufah), configure l'environnement, télécharge et lance le client Folding@home, et gère la configuration dynamique via l'outil `lufah`. Il détecte intelligemment la version du driver hôte pour installer le paquet CUDA le plus adapté et corrige les liens symboliques `libcuda.so` souvent manquants dans certains environnements conteneurisés.
- **Utilisation (dans le template)** :
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/fah-onstart-cuda.sh -o fah-onstart.sh && chmod +x fah-onstart.sh
./fah-onstart.sh  >>fah-onstart.log 2>&1
```

🚨Ce script doit être le dernier à la fin du champ "On-start script / bash commands [...]" de votre template

### 2. fah-onstart.sh _(ancienne version / dépréciée)_
- **Rôle** : Version précédente du script d'initialisation.
 
⚠️ Il est recommandé d'utiliser `fah-onstart-cuda.sh` à la place, qui gère mieux la détection des versions & paquets CUDA à installer,  et évite les blocages lors de relances.

### 3. [fah-watchdog.sh](fah-watchdog.sh)
- **Rôle** : Script de surveillance qui veille à ce que le client FAH fonctionne correctement. S'il détecte une perte de connexion Websocket ou que `lufah` n'arrive plus à commuiniquer avec le client F@h, il force la relance via le script de démarrage.
- **Utilisation (dans le template)** :
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/fah-watchdog.sh -o fah-watchdog.sh && chmod +x fah-watchdog.sh
nohup ./fah-watchdog.sh [intervalle_en_secondes] >fah-watchdog.log 2>&1 & 
(tail -f /workspace/fah-watchdog.log | grep --line-buffered -v "normalement" > /proc/1/fd/1 2>&1) &
```
- **Paramètres** :
  - `[intervalle_en_secondes]` *(Optionnel)* : Fréquence de vérification (minimum 60 secondes, défaut 60).

### 4. [fah-monitoring.sh](fah-monitoring.sh)
- **Rôle** : Script de reporting périodique. Génère un rapport d'état GPU (`nvidia-smi`) toutes les 30 minutes et intègre un test de débit réseau (speedtest) toutes les 12 heures.
- **Utilisation (dans le template)** :
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/fah-monitoring.sh -o fah-monitoring.sh && chmod +x fah-monitoring.sh
nohup ./fah-monitoring.sh >fah-monitoring.log 2>&1 & 
(tail -f /workspace/fah-monitoring.log > /proc/1/fd/1 2>&1) &
```

### 5. [fah-netmon.sh](fah-netmon.sh)
- **Rôle** : Moniteur de trafic réseau. Surveille l'interface principale et déclenche des alertes si la consommation (upload ou download) dépasse des seuils sur des fenêtres glissantes de 5, 20 et 60 minutes.
- **Utilisation (dans le template)** :
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/fah-netmon.sh -o fah-netmon.sh && chmod +x fah-netmon.sh
nohup ./fah-netmon.sh [5M=xxx] [20M=yyy] [60M=zzz] >fah-netmon.log 2>&1 & 
(tail -f /workspace/fah-netmon.log > /proc/1/fd/1 2>&1) &
```
- **Paramètres par défaut** : `5M = 200 Mo`, `20M = 300 Mo`, `60M = 400 Mo`.

### 6. [cleanup_viewer.sh](cleanup_viewer.sh)
- **Rôle** : Nettoie en boucle infinie les gros fichiers de visualisation JSON générés par FAH (`viewerFrame*.json` de plus de 1 Mo) pour éviter la saturation du disque.
- **Utilisation (dans le template)** :
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/cleanup_viewer.sh -o cleanup_viewer.sh && chmod +x cleanup_viewer.sh
nohup ./cleanup_viewer.sh >/dev/null 2>&1 &
```

### 7. [diff_ntp.sh](diff_ntp.sh)
- **Rôle** : Utilitaire de diagnostic temporel. Compare l'heure système locale avec une API publique et un serveur NTP pour détecter d'éventuels décalages d'horloge préjudiciables au bon fonctionnement du client Folding@home
- **Utilisation (dans le template)** :
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/diff_ntp.sh -o diff_ntp.sh && chmod +x diff_ntp.sh
./diff_ntp.sh
```

## Dockerfile
Dockerfile permettant de créer une image simple basée sur Ubuntu 24.04, optimisée pour un environnement non interactif et allégée des caches superflus.
L'image est disponible ici : https://hub.docker.com/r/jwhyfr/fah/tags


Voici la traduction anglaise exacte de ton texte, avec l'indentation de 4 espaces pour préserver le texte brut sans casse de rendu Markdown :




# [EN] FAH-v8 Automation Scripts

This set of shell scripts aims to facilitate the deployment, management, monitoring, and optimization of the Folding@home (v8) client, particularly in containerized environments utilizing single or multi-GPU configurations (such as the Vast.ai infrastructure).

These scripts are designed to run automatically when your Vast.ai instance is created.
To learn how to integrate them into a Vast.ai template and properly configure the "On-start script / bash commands [...]" field, check out the [GPU Cloud Guide available on the Alliance Francophone - Folding@home team website](https://www.alliancefrancophone.org/dossiers/gpu-cloud) and specifically the page dedicated to [template configuration and startup scripts](https://www.alliancefrancophone.org/dossiers/gpu-cloud-02-03) (the guide is in French, but the translation feature built into your browser does a decent job).

Most of these scripts can be executed in the background using the `nohup` command followed by an ampersand (`&`). Their output streams can be redirected to dedicated log files, the contents of which can themselves be piped to the container's standard output (`> /proc/1/fd/1`) to be directly viewable from the Vast.ai interface via the instance's "LOG" button.

Furthermore, most required dependencies (such as `curl`, `bzip2`, `pipx`, `screen`, `libexpat1`, `jq`, etc.) are handled automatically by the initialization scripts or defined in the included `Dockerfile`.

💡 **Note**: Only the initialization script (`fah-onstart-cuda.sh` o r—at worst— its previous version) is strictly required for the Folding@home client to start properly on Vast.ai; using the other monitoring and maintenance scripts remains optional.

## Scripts Description

### 1. [fah-onstart-cuda.sh](fah-onstart-cuda.sh) _(recommended)_
- **Role**: This is the main initialization script. It installs the necessary runtimes (CUDA, Lufah), configures the environment, downloads and launches the Folding@home client, and manages dynamic configuration via the `lufah` tool. It intelligently detects the host driver version to install the most suitable CUDA package and fixes `libcuda.so` symbolic links often missing in certain containerized environments.
- **Usage (in template)**:
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/fah-onstart-cuda.sh -o fah-onstart.sh && chmod +x fah-onstart.sh
./fah-onstart.sh >>fah-onstart.log 2>&1
```

🚨 This script must be placed at the very end of the "On-start script / bash commands [...]" field in your template

### 2. fah-onstart.sh _(older version / deprecated)_
- **Role**: Previous version of the initialization script.
 
⚠️ It is recommended to use `fah-onstart-cuda.sh` instead, which handles CUDA version and package detection much better and avoids freezes upon restart.

### 3. [fah-watchdog.sh](fah-watchdog.sh)
- **Role**: Monitoring script that ensures the FAH client is running properly. If it detects a Websocket connection loss or if `lufah` can no longer communicate with the F@h client, it forces a restart via the startup script.
- **Usage (in template)**:
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/fah-watchdog.sh -o fah-watchdog.sh && chmod +x fah-watchdog.sh
nohup ./fah-watchdog.sh [interval_in_seconds] >fah-watchdog.log 2>&1 & 
(tail -f /workspace/fah-watchdog.log | grep --line-buffered -v "normalement" > /proc/1/fd/1 2>&1) &
```
- **Parameters**:
  - `[interval_in_seconds]` *(Optional)*: Check frequency (minimum 60 seconds, default 60).

### 4. [fah-monitoring.sh](fah-monitoring.sh)
- **Role**: Periodic reporting script. Generates a GPU status report (`nvidia-smi`) every 30 minutes and includes a network speed test every 12 hours.
- **Usage (in template)**:
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/fah-monitoring.sh -o fah-monitoring.sh && chmod +x fah-monitoring.sh
nohup ./fah-monitoring.sh >fah-monitoring.log 2>&1 & 
(tail -f /workspace/fah-monitoring.log > /proc/1/fd/1 2>&1) &
```

### 5. [fah-netmon.sh](fah-netmon.sh)
- **Role**: Network traffic monitor. Monitors the main interface and triggers alerts if bandwidth usage (upload or download) exceeds thresholds over sliding windows of 5, 20, and 60 minutes.
- **Usage (in template)**:
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/fah-netmon.sh -o fah-netmon.sh && chmod +x fah-netmon.sh
nohup ./fah-netmon.sh [5M=xxx] [20M=yyy] [60M=zzz] >fah-netmon.log 2>&1 & 
(tail -f /workspace/fah-netmon.log > /proc/1/fd/1 2>&1) &
```
- **Default parameters**: `5M = 200 MB`, `20M = 300 MB`, `60M = 400 MB`.

### 6. [cleanup_viewer.sh](cleanup_viewer.sh)
- **Role**: Cleans up large JSON visualization files generated by FAH (`viewerFrame*.json` larger than 1 MB) in an infinite loop to prevent disk saturation.
- **Usage (in template)**:
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/cleanup_viewer.sh -o cleanup_viewer.sh && chmod +x cleanup_viewer.sh
nohup ./cleanup_viewer.sh >/dev/null 2>&1 &
```

### 7. [diff_ntp.sh](diff_ntp.sh)
- **Role**: Time diagnostic utility. Compares the local system time with a public API and an NTP server to detect potential clock drift that could impede the Folding@home client operations.
- **Usage (in template)**:
```
curl https://raw.githubusercontent.com/JWhyFR/fah-v8/main/diff_ntp.sh -o diff_ntp.sh && chmod +x diff_ntp.sh
./diff_ntp.sh
```

## Dockerfile
Dockerfile used to create a simple image based on Ubuntu 24.04, optimized for a non-interactive environment and stripped of unnecessary caches.
The image is available here: [https://hub.docker.com/r/jwhyfr/fah/tags](https://hub.docker.com/r/jwhyfr/fah/tags)
