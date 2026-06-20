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
│  │  llama.cpp ── 127.0.0.1:8080  (GPU)          │  │
│  │       │                                       │  │
│  │  Hermes Agent ── 127.0.0.1:8642 / :9119      │  │
│  │       │                                       │  │
│  │  OpenWebUI ── 127.0.0.1:3000                 │  │
│  │  Watchtower (mises à jour auto)               │  │
│  │                                               │  │
│  │  [optionnel] ComfyUI  ── 127.0.0.1:7860      │  │
│  │  [optionnel] Whisper  ── 127.0.0.1:9000      │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

Ollama tourne sur l'hôte pour un accès GPU direct et optimal.
llama.cpp tourne dans Docker avec accès GPU NVIDIA et sert les modèles `.gguf` via une API compatible OpenAI.
OpenWebUI agrège les deux backends.
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

### 4. Configurer Hermes Agent

Créer le fichier `.env` à partir du template :

```bash
cp .env.example .env
# Éditer .env et remplacer HERMES_API_KEY par une vraie clé
openssl rand -hex 32   # génère une clé
```

Initialiser la config Hermes (étape interactive, à faire une seule fois) :

```bash
mkdir -p ~/.hermes
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup
```

Pendant le setup, choisir un provider. Deux options :

**Option A — Ollama (recommandé, accès GPU direct)**

Éditer `~/.hermes/config.yaml` et remplacer les deux premières lignes :

```yaml
model: 'openai/qwen3.6:27b'   # remplacer par le modèle souhaité
providers:
  openai:
    base_url: http://host.docker.internal:11434/v1
    api_key: none
```

Lister les modèles disponibles : `ollama list`

**Option B — llama.cpp**

- Provider : `custom`
- Base URL : `http://llamacpp:8080/v1`
- API key : `none`

### 5. Ajouter des modèles pour llama.cpp

Déposer les fichiers `.gguf` dans le dossier `models/` à la racine du dépôt :

```bash
# Exemple
cp ~/Downloads/mon-modele.gguf models/
```

### 6. Lancer les services core

```bash
docker compose up -d
```

| Service | URL |
|---|---|
| OpenWebUI | http://localhost:3000 |
| llama.cpp (API) | http://localhost:8080 |
| Hermes (API) | http://localhost:8642 |
| Hermes (dashboard) | http://localhost:9119 |

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
| llama.cpp | Docker | Oui |
| Hermes Agent | Docker | Non |
| OpenWebUI | Docker | Non |
| Watchtower | Docker | Non |
| ComfyUI | Docker (optionnel) | Oui |
| Whisper | Docker (optionnel) | Oui |

## Dépannage

### Hermes — Telegram bloqué au démarrage

**Symptôme :** `Telegram bot token already in use (PID XXX). Stop the other gateway first.`

**Cause :** Un fichier lock Telegram ou gateway est resté avec les mauvaises permissions (propriétaire UID 1000 au lieu du user `hermes` du container), ou pointe vers un PID obsolète d'un ancien container.

**Règle à retenir :** Ne jamais accéder ni modifier `~/.hermes` directement depuis le host — laisser uniquement le container y écrire.

**Résolution :**

```bash
# 1. Corriger les permissions des répertoires sensibles
docker exec -u root hermes chown hermes:hermes \
  /opt/data/kanban.db \
  /opt/data/kanban.db.init.lock \
  /opt/data/.local/state/hermes/gateway-locks/

# 2. Supprimer les locks obsolètes
docker exec -u root hermes rm -f \
  /opt/data/gateway.lock \
  /opt/data/.local/state/hermes/gateway-locks/telegram-bot-token-*.lock

# 3. Redémarrer le gateway (s6 le relance automatiquement)
docker exec hermes kill $(docker exec hermes cat /opt/data/gateway.pid | python3 -c "import sys,json; print(json.load(sys.stdin)['pid'])")

# 4. Vérifier la reconnexion (~10 secondes)
sleep 10 && docker exec hermes cat /opt/data/gateway_state.json | python3 -m json.tool
```

Telegram doit passer à `"state": "connected"`.

### Hermes — Erreur de permissions sur kanban.db

**Symptôme :** `PermissionError: [Errno 13] Permission denied: '/opt/data/kanban.db.init.lock'`

**Cause :** Le fichier a été créé ou modifié depuis le host avec l'utilisateur `cut` (UID 1000) au lieu du container.

```bash
docker exec -u root hermes chown hermes:hermes /opt/data/kanban.db /opt/data/kanban.db.init.lock
docker restart hermes
```

## Intégration Gmail

### Prérequis

- Un projet Google Cloud avec les APIs Gmail activées
- Des credentials OAuth 2.0 de type "Desktop app" (`gcp-oauth.keys.json`)

### Configuration initiale (une seule fois)

**1. Générer les credentials OAuth** dans la [Google Cloud Console](https://console.cloud.google.com) :
- APIs & Services → Credentials → Create Credentials → OAuth client ID → Desktop app
- Télécharger le fichier JSON et le renommer `gcp-oauth.keys.json`

**2. Préparer le dossier de config Gmail dans le container** :

```bash
# Créer un dossier dédié (hors du répertoire courant du container pour éviter les conflits)
docker exec -u root hermes mkdir -p /opt/data/.gmail-mcp-config
docker cp gcp-oauth.keys.json hermes:/opt/data/.gmail-mcp-config/gcp-oauth.keys.json
docker exec -u root hermes chown -R hermes:hermes /opt/data/.gmail-mcp-config/
```

**3. Effectuer l'authentification OAuth** depuis le host (Node.js requis) :

Le MCP server `@gongrzhe/server-gmail-autoauth-mcp` écoute sur le port 3000 pour le callback OAuth.
Comme ce port est pris par OpenWebUI, lancer l'auth via un container temporaire sur le port 3001 :

```bash
# Écrire le script d'auth
docker exec hermes node - << 'EOF'  # ou utiliser le script gmail-auth.mjs du projet
EOF

# Lancer l'auth sur le port 3001 avec --network host
docker run --rm --network host \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent:latest \
  node /opt/data/gmail-auth.mjs
```

Visiter l'URL affichée dans le navigateur. Après autorisation, le token est sauvegardé automatiquement.

```bash
# Copier le token dans le dossier de config dédié
docker exec hermes cp /opt/data/gmail-token.json /opt/data/.gmail-mcp-config/credentials.json
docker exec -u root hermes chown hermes:hermes /opt/data/.gmail-mcp-config/credentials.json
```

**4. Vérifier la configuration dans `~/.hermes/config.yaml`** :

```yaml
mcp_servers:
  gmail:
    command: node
    args:
    - /opt/data/.npm/_npx/952459504b2da320/node_modules/.bin/gmail-mcp
    env:
      GMAIL_OAUTH_PATH: /opt/data/.gmail-mcp-config/gcp-oauth.keys.json
      GMAIL_CREDENTIALS_PATH: /opt/data/.gmail-mcp-config/credentials.json
    tools:
      include:
      - search_emails
      - read_email
      - send_email
      - list_emails
      - create_draft
```

**Points importants :**
- Utiliser `command: node` (pas `npx`) pour éviter les timeouts de connexion MCP
- Les fichiers OAuth doivent être dans un sous-dossier (ex. `.gmail-mcp-config/`) et **non à la racine de `/opt/data/`** — sinon le MCP server détecte `gcp-oauth.keys.json` dans son répertoire courant et imprime un message sur stdout qui corrompt le canal JSON-RPC
- Ne jamais laisser `gcp-oauth.keys.json` à la racine de `~/.hermes/` si Gmail MCP est configuré

**5. Redémarrer Hermes** :

```bash
docker restart hermes
```

Les outils Gmail (send_email, search_emails, read_email, etc.) sont alors disponibles pour l'agent.

## Intégration Google Calendar

Utilise le même projet Google Cloud et les mêmes credentials OAuth que Gmail. L'API Calendar doit être activée dans le projet.

### Installation du package (une seule fois)

```bash
docker exec hermes bash -c "
mkdir -p /opt/data/.npm/_calendar-install && \
cd /opt/data/.npm/_calendar-install && \
npm install @cocal/google-calendar-mcp
"
```

### Authentification OAuth

```bash
# Écrire le script d'auth Calendar (utilise les modules Gmail déjà en cache)
docker exec hermes bash -c "cat > /opt/data/calendar-auth.mjs << 'SCRIPT'
import { OAuth2Client } from '/opt/data/.npm/_npx/952459504b2da320/node_modules/google-auth-library/build/src/index.js';
import http from 'http';
import fs from 'fs';

const keys = JSON.parse(fs.readFileSync('/opt/data/.gmail-mcp-config/gcp-oauth.keys.json', 'utf8'));
const { client_id, client_secret } = keys.installed;
const PORT = 3501;
const CALLBACK = 'http://localhost:' + PORT + '/oauth2callback';
const client = new OAuth2Client(client_id, client_secret, CALLBACK);

const authUrl = client.generateAuthUrl({
  scope: ['https://www.googleapis.com/auth/calendar'],
  access_type: 'offline', prompt: 'consent'
});

const server = http.createServer(async (req, res) => {
  if (req.url && req.url.startsWith('/oauth2callback')) {
    const code = new URL(req.url, 'http://localhost:' + PORT).searchParams.get('code');
    const { tokens } = await client.getToken(code);
    fs.writeFileSync('/opt/data/.gmail-mcp-config/calendar-token.json', JSON.stringify(tokens));
    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end('<h1>Google Calendar connecté !</h1>');
    setTimeout(() => { server.close(); process.exit(0); }, 500);
  }
});
server.listen(PORT, '0.0.0.0', () => { console.log('URL:', authUrl); });
SCRIPT"

# Lancer l'auth sur le port 3501 avec --network host
docker run --rm --network host --entrypoint node \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent:latest \
  /opt/data/calendar-auth.mjs
```

Visiter l'URL affichée. Après autorisation, fixer les permissions :

```bash
docker exec -u root hermes chown hermes:hermes /opt/data/.gmail-mcp-config/calendar-token.json
```

### Configuration dans `~/.hermes/config.yaml`

```yaml
mcp_servers:
  google-calendar:
    command: node
    args:
    - /opt/data/.npm/_calendar-install/node_modules/.bin/google-calendar-mcp
    env:
      GOOGLE_OAUTH_CREDENTIALS: /opt/data/.gmail-mcp-config/gcp-oauth.keys.json
      GOOGLE_CALENDAR_MCP_TOKEN_PATH: /opt/data/.gmail-mcp-config/calendar-token.json
    tools:
      include:
      - list-calendars
      - list-events
      - search-events
      - get-event
      - create-event
      - update-event
      - delete-event
      - get-freebusy
      - respond-to-event
```

```bash
docker restart hermes
```

**Outils disponibles :** list-calendars, list-events, search-events, get-event, create-event, update-event, delete-event, get-freebusy, respond-to-event.
