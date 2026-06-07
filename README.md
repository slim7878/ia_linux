# ia_linux

Infrastructure IA locale sous Ubuntu avec GPU NVIDIA.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                        Hôte                         │
│                                                     │
│  Ollama (natif) ──── port 11434                     │
│       │                                             │
│  ┌────┴──────────────────────────────────────────┐  │
│  │                    Docker                     │  │
│  │                                               │  │
│  │  OpenWebUI ── 127.0.0.1:3000                 │  │
│  │  Watchtower (mises à jour auto)               │  │
│  │                                               │  │
│  │  [optionnel] ComfyUI  ── 127.0.0.1:7860      │  │
│  │  [optionnel] Whisper  ── 127.0.0.1:9000      │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

Ollama tourne sur l'hôte pour un accès GPU direct et optimal.
Tous les ports sont liés à `127.0.0.1` (accès local uniquement).

## Prérequis

- Ubuntu 24.04+ (resolute)
- GPU NVIDIA avec drivers installés

## Installation

### 1. Docker

```bash
bash scripts/install_docker.sh
```

Se déconnecter/reconnecter après pour activer le groupe `docker`.

### 2. Support GPU (NVIDIA Container Toolkit)

```bash
bash scripts/install_nvidia_toolkit.sh
```

### 3. Ollama (sur l'hôte)

```bash
bash scripts/install_ollama.sh
```

Ollama est configuré pour écouter sur `0.0.0.0:11434` afin d'être accessible depuis Docker.

### 4. Lancer les services core

```bash
docker compose up -d
```

| Service | URL |
|---|---|
| OpenWebUI | http://localhost:3000 |

## Services optionnels

Activer un service optionnel (profile) :

```bash
# ComfyUI (génération d'images)
docker compose --profile comfyui up -d

# Whisper (transcription audio)
docker compose --profile whisper up -d

# Tout en même temps
docker compose --profile comfyui --profile whisper up -d
```

| Service | URL | Profile |
|---|---|---|
| ComfyUI | http://localhost:7860 | `comfyui` |
| Whisper | http://localhost:9000 | `whisper` |

## Stack complète

| Composant | Déploiement | GPU |
|---|---|---|
| Ollama | Hôte (natif) | Oui |
| OpenWebUI | Docker | Non |
| Watchtower | Docker | Non |
| ComfyUI | Docker (optionnel) | Oui |
| Whisper | Docker (optionnel) | Oui |
