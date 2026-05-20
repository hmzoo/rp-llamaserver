# API Reference — rp-llamaserver

Runpod serverless worker exposant une interface OpenAI-compatible via llama.cpp.

**Base URL :** `https://api.runpod.ai/v2/{ENDPOINT_ID}`  
**Auth :** Header `Authorization: Bearer {RUNPOD_API_KEY}`

---

## Endpoints Runpod

### POST `/runsync`
Envoi synchrone — attend la réponse avant de retourner (timeout 90 s).

### POST `/run`
Envoi asynchrone — retourne immédiatement un `id` à poller.

### GET `/status/{job_id}`
Récupère l'état et le résultat d'un job asynchrone.

### POST `/cancel/{job_id}`
Annule un job en attente.

### GET `/health`
Statut du worker (workers actifs, jobs en file).

---

## Corps de la requête

```json
{
  "input": { ... }
}
```

Le champ `input` supporte deux modes : **simplifié** et **OpenAI direct**.

---

## Mode simplifié

Le handler route automatiquement vers `/v1/completions` (prompt string) ou `/v1/chat/completions` (messages array).

### Champs `input`

| Champ      | Type              | Défaut  | Description |
|------------|-------------------|---------|-------------|
| `prompt`   | `string`          | —       | Prompt texte brut. Mutuellement exclusif avec `messages`. |
| `messages` | `array<Message>`  | —       | Liste de messages au format chat. Mutuellement exclusif avec `prompt`. |
| `stream`   | `boolean`         | `false` | Streaming SSE de la réponse. |

### Objet `Message`

| Champ     | Type     | Valeurs possibles              | Description |
|-----------|----------|-------------------------------|-------------|
| `role`    | `string` | `"system"`, `"user"`, `"assistant"` | Rôle de l'émetteur |
| `content` | `string` ou `array<ContentPart>` | — | Texte simple ou contenu multimodal |

### Objet `ContentPart` (multimodal)

| Champ       | Type     | Description |
|-------------|----------|-------------|
| `type`      | `string` | `"text"` ou `"image_url"` |
| `text`      | `string` | Texte (si `type: "text"`) |
| `image_url` | `object` | Objet `{ "url": "..." }` (si `type: "image_url"`) |

L'URL image peut être :
- Une URL distante : `"https://example.com/image.jpg"`
- Une data URI base64 : `"data:image/jpeg;base64,/9j/4AA..."` 

---

## Mode OpenAI direct

Permet d'appeler un endpoint OpenAI précis avec un payload personnalisé.

### Champs `input`

| Champ          | Type     | Description |
|----------------|----------|-------------|
| `openai_route` | `string` | Route cible : `/v1/models`, `/v1/completions` ou `/v1/chat/completions` |
| `openai_input` | `object` | Payload transmis tel quel à l'API OpenAI locale (llama.cpp) |

---

## Exemples de requêtes

### Texte simple

```bash
curl -X POST "https://api.runpod.ai/v2/$ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "prompt": "Qui es-tu ?",
      "stream": false
    }
  }'
```

### Chat (avec system prompt)

```bash
curl -X POST "https://api.runpod.ai/v2/$ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "messages": [
        { "role": "system", "content": "Tu es un assistant concis." },
        { "role": "user", "content": "Explique la photosynthèse en une phrase." }
      ],
      "stream": false
    }
  }'
```

### Multimodal — image par URL

```bash
curl -X POST "https://api.runpod.ai/v2/$ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "messages": [
        {
          "role": "user",
          "content": [
            { "type": "text", "text": "Que vois-tu sur cette image ?" },
            { "type": "image_url", "image_url": { "url": "https://example.com/photo.jpg" } }
          ]
        }
      ],
      "stream": false
    }
  }'
```

### Multimodal — image base64

```bash
IMAGE_B64=$(base64 -w 0 < ./image.jpg)

curl -X POST "https://api.runpod.ai/v2/$ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary @- <<< '{
    "input": {
      "messages": [
        {
          "role": "user",
          "content": [
            { "type": "text", "text": "Décris cette image." },
            { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,'"$IMAGE_B64"'" } }
          ]
        }
      ],
      "stream": false
    }
  }'
```

### Listing des modèles disponibles

```bash
curl -X POST "https://api.runpod.ai/v2/$ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "openai_route": "/v1/models",
      "openai_input": {}
    }
  }'
```

### Job asynchrone + polling

```bash
# 1. Envoi
JOB_ID=$(curl -s -X POST "https://api.runpod.ai/v2/$ENDPOINT_ID/run" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input":{"prompt":"Bonjour","stream":false}}' | jq -r '.id')

# 2. Polling
curl "https://api.runpod.ai/v2/$ENDPOINT_ID/status/$JOB_ID" \
  -H "Authorization: Bearer $RUNPOD_API_KEY"
```

---

## Format de réponse

### Réponse synchrone complète (non-stream)

```json
{
  "id": "sync-xxxxxxxx",
  "status": "COMPLETED",
  "output": [
    {
      "id": "chatcmpl-xxxx",
      "object": "chat.completion",
      "model": "Qwen3VL-4B-Instruct-Q4_K_M",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "Réponse du modèle..."
          },
          "finish_reason": "stop"
        }
      ],
      "usage": {
        "prompt_tokens": 42,
        "completion_tokens": 18,
        "total_tokens": 60
      }
    }
  ]
}
```

### Statuts possibles

| Status       | Description |
|--------------|-------------|
| `IN_QUEUE`   | Job en attente d'un worker |
| `IN_PROGRESS`| Job en cours d'exécution |
| `COMPLETED`  | Terminé avec succès — `output` disponible |
| `FAILED`     | Erreur — voir `error` dans la réponse |
| `CANCELLED`  | Annulé par l'utilisateur |
| `TIMED_OUT`  | Timeout dépassé |

---

## Variables d'environnement du worker

| Variable                  | Description |
|---------------------------|-------------|
| `LLAMA_CACHED_MODEL`      | ID HuggingFace du modèle (ex: `Qwen/Qwen3-VL-4B-Instruct-GGUF`) |
| `LLAMA_CACHED_GGUF_PATH`  | Chemin relatif du fichier GGUF dans le repo |
| `LLAMA_CACHED_MMPROJ_PATH`| Chemin relatif du mmproj (modèles VLM uniquement) |
| `LLAMA_ARGS`              | Arguments supplémentaires pour llama-server |
| `MAX_CONCURRENCY`         | Nombre max de jobs parallèles (défaut: 8) |

---

## Script de test

Le script `test_endpoint.sh` à la racine du projet facilite les tests :

```bash
./test_endpoint.sh [PROMPT] [IMAGE_PATH] [SYSTEM_PROMPT_FILE]
```

| Argument            | Description |
|---------------------|-------------|
| `PROMPT`            | Texte de la requête (défaut: `"What is your name?"`) |
| `IMAGE_PATH`        | Chemin vers une image locale (optionnel, `''` pour ignorer) |
| `SYSTEM_PROMPT_FILE`| Fichier contenant le system prompt (optionnel) |

Exemples :
```bash
./test_endpoint.sh "Qui es-tu ?"
./test_endpoint.sh "Décris l'image" "./photo.jpg"
./test_endpoint.sh "Génère une scène" "" "./gen_img_middleage.md"
./test_endpoint.sh "Analyse" "./img.jpg" "./system.md"
```
