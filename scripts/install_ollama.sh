#!/bin/bash
set -e

# Ollama — installé sur l'hôte (hors Docker) pour accès direct au GPU
curl -fsSL https://ollama.com/install.sh | sh

# S'assurer qu'Ollama écoute sur toutes les interfaces (pas seulement localhost)
# afin d'être accessible depuis les conteneurs Docker via host-gateway
sudo mkdir -p /etc/systemd/system/ollama.service.d
cat <<EOF | sudo tee /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama

echo "Ollama installé et configuré pour écouter sur 0.0.0.0:11434"
