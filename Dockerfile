# Base image
FROM ubuntu:24.04

# Définir l'environnement pour éviter les prompts interactifs
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Etc/UTC

# Mise à jour + installation des paquets
RUN apt-get update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
                curl \
                bzip2 \
                pipx \
                screen \
                libexpat1 && \
    pipx ensurepath && \
    apt-get purge -y $(dpkg-query -W -f='${Package}\n' | grep -- '-doc$') || true && \
    apt-get autoremove -y && apt-get clean && \
    rm -rf \
                /var/lib/apt/lists/* \
                /var/cache/apt/* \
                /root/.cache \
                /usr/share/doc/* \
                /usr/share/man/* \
                /var/tmp/* \
                /var/log/* \
                /tmp/*

# Répertoire de travail
WORKDIR /workspace

# Commande par défaut
CMD ["bash"]
