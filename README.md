<p align="center">
  <img src="assets/recallwhisper-social-preview.png" alt="RecallWhisper — Private speech. Local memory." width="1280">
</p>

# RecallWhisper

[中文](README.zh-CN.md)

Private Android ambient voice capture and summarization with all durable data stored on the phone.

## Data flow

```text
Microphone → encrypted local WAV → transcription API
           → local raw transcript → summarization API
           → local summary/search/export
```

- Native Kotlin foreground service and Quick Settings tile
- Silero VAD with configurable 5–60 second conversation pause tolerance
- Per-file AES-256-GCM keys wrapped by Android Keystore
- Room metadata, raw transcription responses, transcripts, and summaries
- Direct OpenAI-compatible transcription and summarization endpoints
- Wi-Fi-only processing by default; cellular is opt-in
- Local playback, transcript search, deletion, API playground, and JSON export

## Configure RecallWhisper

In Settings, configure the transcription and summarization URL, token, and
model separately. Each URL must include the `/v1` API prefix. HTTPS is required
unless **Allow insecure HTTP** is explicitly enabled for a trusted development
network.

Settings → Debug and API playground can list summarization models, edit the
local system prompt, send arbitrary text, tune generation parameters, and
inspect response latency and errors. It also includes an authenticated
transcription-server health and model-discovery check.

“Export all data as JSON” opens Android’s document picker and writes segment
metadata, raw transcription results, transcripts, summaries, processing state,
and checksums to a user-selected file. Audio remains separately encrypted in
private app storage.

## Self-hosted processing example

This example uses two independent local services:

```text
RecallWhisper
  ├─ /v1/audio/transcriptions → OpenASR + X-ASR zh/en
  └─ /v1/chat/completions     → llama.cpp + Qwen3.5 4B GGUF
```

The separation is intentional: RecallWhisper stores distinct URLs, bearer
tokens, and model IDs for transcription and summarization.

### 1. Run OpenASR with X-ASR zh/en

Install the current `openasr` binary from the
[OpenASR releases](https://github.com/QuintinShaw/openasr/releases), then pull
the recommended Q8 bilingual X-ASR pack:

```sh
openasr pull xasr-zh-en:q8
openasr transcribe sample.wav --model xasr-zh-en
```

The [X-ASR model card](https://huggingface.co/OpenASR/xasr-zh-en) documents
the `fp16`, `q8`, and `q4` packs. Q8 is a practical default; use Q4 when memory
is tighter.

Create a bearer token and start the server:

```sh
openasr apikey create --name recallwhisper
export OPENASR_TOKEN='replace-with-the-created-token'
openasr serve --help
openasr serve --addr 0.0.0.0:9099 --model xasr-zh-en --pairing-admin-token-env OPENASR_TOKEN
```

Save the API key when it is shown; RecallWhisper uses it as the transcription
token. This example uses port 9099 so it does not conflict with llama.cpp on
port 8080; OpenASR’s default is `127.0.0.1:8080`. Consult the [OpenASR server
documentation](https://openasr.org/docs/server/) before binding outside
loopback: remote serving requires authentication and TLS/pairing. The server
exposes the OpenAI-compatible `/v1/models` and `/v1/audio/transcriptions`
routes that RecallWhisper calls.

### 2. Run llama.cpp with Qwen3.5 4B GGUF

The official [Qwen3.5 4B model](https://huggingface.co/Qwen/Qwen3.5-4B) does
not itself contain GGUF files. This example uses Unsloth’s
[Qwen3.5-4B GGUF repository](https://huggingface.co/unsloth/Qwen3.5-4B-GGUF)
and its 2.74 GB `Q4_K_M` quantization.

Create a working directory, download the model, and generate an API key:

```sh
mkdir -p recallwhisper-llm/models
cd recallwhisper-llm

curl -fL \
  'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf?download=true' \
  -o models/Qwen3.5-4B-Q4_K_M.gguf
```

Create `compose.yaml` in recallwhisper-llm/ with the following content, replacing `<SET_YOUR_LLAMA_API_KEY>` with a secure value:

```yaml
services:
  llama:
    # Select one of the following images based on your host hardware.
    image: ghcr.io/ggml-org/llama.cpp:server    # CPU-only image
    # image: ghcr.io/ggml-org/llama.cpp:server-cuda   # For NVIDIA GPU hosts
    # image: ghcr.io/ggml-org/llama.cpp:server-vulkan # For AMD/Intel GPU hosts
    restart: unless-stopped
    ports:
      - "8181:8080"
    volumes:
      - ./models:/models:ro
    environment:
      LLAMA_API_KEY: <SET_YOUR_LLAMA_API_KEY>
    command:
      - --model
      - /models/Qwen3.5-4B-Q4_K_M.gguf
      - --alias
      - qwen3.5-4b
      - --host
      - 0.0.0.0
      - --port
      - "8080"
      - --ctx-size
      - "16384"
      - --parallel
      - "1"
      - --reasoning
      - "off"
    # For AMD or Intel GPU hosts, uncomment the following lines to enable Vulkan GPU offload:
    # devices:
    # - /dev/null:/dev/null
    # For NVIDIA GPU hosts, uncomment the following line to enable CUDA GPU offload:
    # deploy:
    #   resources:
    #     reservations:
    #       devices:
    #         - capabilities: [gpu]
```

Start the service:

```sh
docker compose up -d
```

This uses llama.cpp’s server-only image, documented in the official
[Docker guide](https://github.com/ggml-org/llama.cpp/blob/master/docs/docker.md).
The `--alias` value becomes the model ID returned by `/v1/models`. Using
`--reasoning off` complements RecallWhisper’s non-thinking summary requests. See the
[llama.cpp server reference](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
for API-key, TLS, GPU-offload, context, and concurrency options.

For an GPU host, use `ghcr.io/ggml-org/llama.cpp:server-cuda` or `ghcr.io/ggml-org/llama.cpp:server-vulkan`. Keep the
CPU image when portability matters more than generation speed.

### 3. Expose both APIs safely

Do not publish either plain-HTTP port directly to the internet. A small reverse
proxy can terminate trusted HTTPS while both inference servers remain bound to
loopback. With the ports used above, a
[Caddy reverse-proxy](https://caddyserver.com/docs/quick-starts/reverse-proxy)
configuration can be as small as:

```caddyfile
asr.example.com {
    reverse_proxy 127.0.0.1:9099
}

llm.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

Keep OpenASR and llama.cpp authentication enabled even behind the proxy. If
you intentionally use private-LAN HTTP instead, bind the required service port
to the LAN interface, firewall it to trusted clients, and enable
**Allow insecure HTTP** in RecallWhisper. That setting permits audio and bearer
tokens to cross the network unencrypted, so it is unsuitable for public or
untrusted networks.

### 4. Enter the settings in RecallWhisper

| Setting | Example |
| --- | --- |
| Transcription URL | `https://asr.example.com/v1` |
| Transcription token | Token from `openasr apikey create --name recallwhisper` |
| Transcription model | `xasr-zh-en` |
| Summarization URL | `https://llm.example.com/v1` |
| Summarization token | `<SET_YOUR_LLAMA_API_KEY>` from `compose.yaml` |
| Summarization model | `qwen3.5-4b` |
| Summary language | `Same as transcript` or a specific language |

Save Settings, then open **Debug and API playground**. Verify the transcription
health check, load the summarization model list, and send a short JSON-mode test
before enabling continuous processing.

### Troubleshooting

- **404 from either server:** the configured URL probably omits `/v1` or adds
  an endpoint path that RecallWhisper appends itself.
- **401 Unauthorized:** verify the transcription and summarization tokens
  independently; they are deliberately not shared.
- **Cleartext HTTP rejected:** use trusted HTTPS, or explicitly enable insecure
  HTTP only for a controlled development LAN.
- **TLS certificate error:** use a certificate trusted by Android. Enabling
  insecure HTTP does not disable HTTPS certificate validation.
- **Model not found:** check `/v1/models`. RecallWhisper’s configured model must
  match `xasr-zh-en` or the llama.cpp `--alias` exactly.
- **No final summary text:** keep Qwen thinking disabled as shown. RecallWhisper
  expects final content in `choices[0].message.content`, not only a reasoning
  field.
- **Container exits during startup:** check `docker compose logs llama`, confirm
  the GGUF path and permissions, and update the llama.cpp image because
  Qwen3.5 support requires a recent build.

## Build

```sh
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```
