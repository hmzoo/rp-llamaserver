# rp-llamaserver

Worker serverless Runpod pour exécuter un modèle GGUF via `llama-server` (llama.cpp) avec interface compatible OpenAI.

Ce dépôt est une version synthétique orientée déploiement, inspirée de:
- `inference-worker/README.md`
- `inference-worker/docs/cached.md`

## Objectif

Fournir un endpoint Runpod serverless capable de servir un modèle GGUF spécifique avec:
- API compatible OpenAI
- support du streaming
- support du cache de modèles Runpod (utilisé comme fallback)

## Modèle embarqué dans l'image (cold start rapide)

Le `Dockerfile` télécharge et embarque le GGUF + mmproj dans l'image (`/models/model.gguf` et `/models/mmproj.gguf`). Au démarrage, `start.sh` utilise **en priorité** ces fichiers locaux (disque local → chargement en quelques secondes) et ne retombe sur le cache Runpod (`/runpod-volume`) que s'ils sont absents.

Pour changer de modèle, surcharge les build args:

```bash
docker build \
  --build-arg MODEL_GGUF_URL=https://huggingface.co/<org>/<repo>/resolve/main/<fichier>.gguf \
  --build-arg MMPROJ_URL=https://huggingface.co/<org>/<repo>/resolve/main/mmproj-<...>.gguf \
  -t ton-image .
```

## Endpoints supportés

Le worker expose les routes OpenAI suivantes:
- `v1/models`
- `v1/chat/completions`
- `v1/completions`

## Structure du projet

- `src/start.sh`: démarre `llama-server` sur le port `3098`, vérifie son démarrage, puis lance le handler Runpod.
- `src/handler.py`: handler async Runpod, choisit l’engine et stream la réponse.
- `src/engine.py`: adaptation des entrées vers les routes OpenAI et appel de l’API locale.
- `src/find_cached.py`: résout le chemin local d’un modèle GGUF mis en cache par Runpod.
- `src/utils.py`: parsing des entrées job.

## Variables d’environnement

### Obligatoires / importantes

- `LLAMA_SERVER_CMD_ARGS`
  - Arguments passés à `llama-server`.
  - Exemple (sans cache): `-hf unsloth/gemma-3-270m-it-GGUF:IQ2_XXS --ctx-size 4096 -ngl 999`
  - Ne jamais définir `--port` (le worker force `3098`).

- `MAX_CONCURRENCY`
  - Concurrence max côté handler Runpod.
  - Valeur par défaut: `8`.

### Recommandées pour le cache Runpod

- `LLAMA_CACHED_MODEL`
  - ID du modèle Hugging Face.
  - Exemple: `unsloth/gemma-3-270m-it-GGUF`

- `LLAMA_CACHED_GGUF_PATH`
  - Chemin du fichier GGUF dans le repo HF.
  - Exemple: `gemma-3-270m-it-Q8_0.gguf`

- `LLAMA_CACHED_MMPROJ_PATH` (optionnel, multimodal)
  - Chemin du fichier `mmproj` dans le repo HF.
  - Exemple: `mmproj-Qwen3VL-4B-Instruct-Q8_0.gguf`
  - Si défini, le script ajoute automatiquement `-mm <chemin_local_cache>`.

Quand ces variables sont définies, `src/start.sh` calcule automatiquement le `-m <chemin_local_cache>` via `src/find_cached.py`.

## Configuration recommandée (modèle GGUF spécifique)

Pour charger un modèle précis en mode cache:

1. Dans la config Runpod, renseigner le champ **Model** avec l’URL HF du modèle.
   - Exemple: `https://huggingface.co/unsloth/gemma-3-270m-it-GGUF`
2. Définir:
   - `LLAMA_CACHED_MODEL=unsloth/gemma-3-270m-it-GGUF`
   - `LLAMA_CACHED_GGUF_PATH=gemma-3-270m-it-Q8_0.gguf`
3. Dans `LLAMA_SERVER_CMD_ARGS`, mettre uniquement les options runtime (sans `-hf`, sans `-m`, sans `--port`).
   - Exemple: `--ctx-size 4096 --temp 0.7 --top-p 0.9 -ngl 999`
4. Démarrer le worker: le script résout le chemin cache et lance `llama-server` automatiquement.

## Configuration prête à l'emploi (Qwen3-VL-4B-Instruct-GGUF)

Modèle demandé:
- Repo HF: `Qwen/Qwen3-VL-4B-Instruct-GGUF`
- LLM: `Qwen3VL-4B-Instruct-Q4_K_M.gguf`
- MMProj: `mmproj-Qwen3VL-4B-Instruct-Q8_0.gguf`

Dans Runpod (Endpoint Serverless):

1. Champ **Model**:
  - `https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF`
2. Variables d'environnement:
  - `LLAMA_CACHED_MODEL=Qwen/Qwen3-VL-4B-Instruct-GGUF`
  - `LLAMA_CACHED_GGUF_PATH=Qwen3VL-4B-Instruct-Q4_K_M.gguf`
  - `LLAMA_CACHED_MMPROJ_PATH=mmproj-Qwen3VL-4B-Instruct-Q8_0.gguf`
  - `LLAMA_SERVER_CMD_ARGS=--ctx-size 8192 --temp 0.7 --top-p 0.8 --top-k 20 -ngl 999 -fa on -np 8 -kvu -b 4096 -ub 1024 -ctk q8_0 -ctv q8_0`
  - `MAX_CONCURRENCY=8`

Notes:
- Ne pas mettre `-hf`, `-m`, `-mm` ni `--port` dans `LLAMA_SERVER_CMD_ARGS` quand vous utilisez les variables de cache ci-dessus.
- `-np` doit correspondre à `MAX_CONCURRENCY` pour éviter la file d'attente côté llama.cpp.
- `-kvu` (KV unifié) est **indispensable** avec `-np` : sans lui, llama.cpp **divise** le contexte en slots (`n_ctx_slot = ctx / np`). Avec `-np 8` et `--ctx-size 8192`, chaque slot n'aurait que **1024 tokens** → générations tronquées (une image Qwen-VL consomme déjà ~1000 tokens). `-kvu` partage un buffer KV unique de 8192 tokens entre tous les slots.
- `-ctk q8_0 -ctv q8_0` quantifie le cache KV : moins de VRAM, plus de marge pour les slots. À retirer si la qualité se dégrade.
- `--mmproj-auto` est activé par défaut (le `-mm` est injecté automatiquement par `start.sh` via le cache) ; inutile de l'ajouter.

### Paramètres Runpod manquants (UI Endpoint)

- Container start command:
  - Recommandé: laisser vide (le Dockerfile a déjà `ENTRYPOINT ["/bin/sh", "-c", "/work/start.sh"]`).
  - Si vous devez forcer une valeur: `/bin/sh -c /work/start.sh`.

- Container disk (GB):
  - Minimum recommandé: `5`.
  - Recommandé en pratique: `10` (plus confortable pour logs/fichiers temporaires).
  - Le modèle HF en cache Runpod est stocké sous `/runpod-volume/...` et ne dépend pas principalement de ce disque container.

- Expose HTTP ports:
  - Aucun port à exposer pour ce worker serverless.

- Expose TCP ports:
  - Aucun port à exposer.

Pourquoi aucun port:
- `llama-server` écoute en interne sur `3098` et est consommé localement par le handler Python.
- Runpod Serverless communique avec le worker via le runtime Runpod, pas via un port public de votre conteneur.

## Pourquoi le cache est recommandé

Sans cache, chaque nouveau worker peut retélécharger le modèle HF au démarrage, ce qui augmente latence et coûts. Le mécanisme de cache Runpod réduit fortement ce temps de warm-up.

## Format des requêtes (Runpod)

Le handler attend `job.input` avec l’un des formats suivants:

### Completion

```json
{
  "input": {
    "prompt": "How are you?",
    "stream": false
  }
}
```

### Chat completion

```json
{
  "input": {
    "messages": [
      {"role": "system", "content": "You are concise."},
      {"role": "user", "content": "Explain GGUF in one sentence."}
    ],
    "stream": true
  }
}
```

### Multimodal avec image_url (URL distante)

```json
{
  "input": {
    "messages": [
      {
        "role": "system",
        "content": "You are a vision assistant. Reply in French."
      },
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Décris cette image en 5 points courts."
          },
          {
            "type": "image_url",
            "image_url": {
              "url": "https://images.unsplash.com/photo-1518770660439-4636190af475"
            }
          }
        ]
      }
    ],
    "stream": false
  }
}
```

### Multimodal avec image_url (base64)

```json
{
  "input": {
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Que vois-tu dans cette image ?"
          },
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD..."
            }
          }
        ]
      }
    ],
    "stream": false
  }
}
```

Exemple de génération base64 locale (Linux):

```bash
IMG_B64=$(base64 -w 0 ./image.jpg)
```

Puis remplacer `...` dans le payload par la variable encodée.

## Notes opérationnelles

- Le port `3098` est réservé et géré automatiquement.
- Le worker renvoie des chunks de streaming au format `data: ...` quand `stream=true`.
- Si `LLAMA_SERVER_CMD_ARGS` n’est pas défini, `src/start.sh` applique une valeur par défaut.

## Logs de debug (modèle/cache)

Les messages Runpod du type:
- `image ready, model not found`
- `image ready, initializing model files`
- `image ready, model download failed`

proviennent du runtime Runpod (pas directement de `llama-server`).

Pour obtenir plus de détail côté worker, `src/start.sh` déclenche automatiquement un diagnostic quand la résolution du cache échoue (`LLAMA_CACHED_MODEL`, `LLAMA_CACHED_GGUF_PATH` ou `LLAMA_CACHED_MMPROJ_PATH`).

Ce diagnostic affiche notamment:
- le dossier de cache utilisé (`/runpod-volume/huggingface-cache/hub`),
- les variantes de nom de modèle testées,
- les snapshots trouvés,
- les chemins de fichiers GGUF/mmproj réellement vérifiés.

Vous verrez ces informations dans les logs du conteneur avec le préfixe `start.sh:`.

## Références

- Source principale: https://github.com/Jacob-ML/inference-worker
- Doc cache modèles: https://github.com/Jacob-ML/inference-worker/blob/master/docs/cached.md
- Model caching Runpod: https://docs.runpod.io/serverless/endpoints/model-caching
