# Run Ternary Bonsai 27B Locally

[![CI](https://github.com/theabbie/ternary-bonsai-action/actions/workflows/ci.yml/badge.svg)](https://github.com/theabbie/ternary-bonsai-action/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Download and run [Ternary Bonsai 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf) directly on a GitHub Actions runner.

Inference is local to the runner. Prompts and responses are not sent to Hugging Face, Together, or another inference API. Hugging Face is used only to download the public GGUF model.

## How it works

The Action:

1. Restores the model and runtime from the GitHub Actions cache when available.
2. Installs the Hugging Face CLI in an isolated environment.
3. Downloads the 7.17 GB `Ternary-Bonsai-27B-Q2_0.gguf` file at a pinned revision.
4. Downloads and verifies PrismML's pinned llama.cpp CPU runtime.
5. Starts llama-server on the runner loopback interface.
6. Sends the prompt to the local OpenAI-compatible server.
7. Stops the server and returns the answer, reasoning, timings, and response file.

No network inference provider is used.

## Usage

```yaml
name: Local Ternary Bonsai

on:
  workflow_dispatch:
    inputs:
      prompt:
        description: Prompt
        required: true

permissions:
  contents: read

jobs:
  inference:
    runs-on: ubuntu-latest
    timeout-minutes: 90
    steps:
      - name: Run Ternary Bonsai 27B locally
        id: bonsai
        uses: theabbie/ternary-bonsai-action@v1
        with:
          prompt: ${{ inputs.prompt }}
          max-tokens: "2048"

      - name: Write response to the summary
        env:
          RESPONSE: ${{ steps.bonsai.outputs.response }}
        run: printf '%s\n' "$RESPONSE" >> "$GITHUB_STEP_SUMMARY"
```

The model is public, so `hf-token` is optional. A read-only Hugging Face token can reduce anonymous download restrictions:

```yaml
with:
  hf-token: ${{ secrets.HF_TOKEN }}
  prompt: Write an essay about ternary neural networks.
```

## Runner requirements

The current release supports Linux x64 runners. Use `ubuntu-latest` or a compatible self-hosted Linux x64 runner.

The model file is exactly 7,165,121,600 bytes. A 4096-token context requires roughly 8.4 GB of memory including weights and runtime overhead. Standard public-repository Ubuntu runners have enough memory for the default configuration, but local CPU inference is slower than hosted GPU inference.

The first run downloads the model and may take several minutes. The default cache consumes about 7.3 GB of the repository's GitHub Actions cache allowance. Later runs can restore it instead of downloading it again.

## Natural stopping

`max-tokens` is optional. When omitted, llama.cpp lets the model stop naturally. Set it when a workflow needs a cost, time, or output ceiling.

Ternary Bonsai 27B is a reasoning model. Small ceilings can be consumed by reasoning before a final answer is produced.

## Prompt files

Check out the repository before using `prompt-file`:

```yaml
- uses: actions/checkout@v7

- name: Run a prompt file
  id: bonsai
  uses: theabbie/ternary-bonsai-action@v1
  with:
    prompt-file: .github/prompts/review.txt
```

Use either `prompt` or `prompt-file`.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `prompt` | One of | | User prompt |
| `prompt-file` | One of | | Path to a UTF-8 prompt file |
| `system-prompt` | No | `You are a helpful assistant.` | System prompt |
| `hf-token` | No | | Token used only for the model download |
| `cache` | No | `true` | Cache the model and runtime |
| `context-size` | No | `4096` | Local llama.cpp context size |
| `max-tokens` | No | | Optional completion ceiling |
| `temperature` | No | `0.7` | Sampling temperature |
| `top-p` | No | `0.95` | Nucleus sampling value |
| `response-file` | No | `bonsai-response.txt` | Response output path |

## Outputs

| Output | Description |
| --- | --- |
| `response` | Generated final answer |
| `response-file` | Absolute response file path |
| `reasoning` | Model reasoning returned by llama.cpp |
| `timings` | JSON timing data returned by llama.cpp |
| `model-path` | Absolute local GGUF path |
| `cache-hit` | Whether the GitHub Actions cache was restored |

For long responses, use `response-file` instead of passing `response` between steps.

## Pinned artifacts

| Artifact | Revision |
| --- | --- |
| Ternary Bonsai 27B GGUF | `abbae723028d71be674e71e1a71201a6f43fab22` |
| PrismML llama.cpp | `prism-b9596-9fcaed7` |

The runtime archive is verified with SHA-256 before extraction.

## Security

The local llama-server binds only to `127.0.0.1` and is stopped before the Action finishes.

Pass an optional Hugging Face credential through GitHub Actions secrets. The token is used only by `hf download`.

Pin the Action to a full commit SHA when your security policy requires immutable dependencies.

## License and attribution

This Action is licensed under the [MIT License](LICENSE).

Ternary Bonsai 27B is published by PrismML under the Apache 2.0 license. The model is not included in this repository. This project is an independent community integration and is not affiliated with or endorsed by PrismML or Hugging Face.
