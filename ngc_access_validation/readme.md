# Verify NGC Image Access with NGC CLI

Docs: https://docs.ngc.nvidia.com/cli/cmd.html

## Install & Configure

Download the CLI: https://ngc.nvidia.com/setup/installers/cli

```bash
ngc config set
```

You'll be prompted for:
- **API Key** — generate at https://org.ngc.nvidia.com/setup/api-key
- **CLI output format** — `ascii` (default), `csv`, or `json`
- **Organization** — select which org the key belongs to

Verify your configuration:

```bash
ngc config current
ngc user who
```

## Verify Image Access

To check if your key has pull access to a specific container image, list its tags.

For example, to check access to the [Multi-LLM NIM](https://catalog.ngc.nvidia.com/orgs/nim/teams/nvidia/containers/llm-nim) image (`nvcr.io/nim/nvidia/llm-nim`):

```bash
ngc registry image list nim/nvidia/llm-nim
```

(see [registry image commands](https://docs.ngc.nvidia.com/cli/cmd_registry.html#image_repeat1) for full syntax)

If you have access, you'll see the available tags:

```
+--------+--------------+------------+---------+
| Tag    | Updated Date | Image Size | Signed? |
+--------+--------------+------------+---------+
| 1.15   | Jan 29, 2026 | 9.68 GB    | True    |
| latest | Jan 29, 2026 | 9.68 GB    | True    |
| 1.15.5 | Jan 29, 2026 | 9.68 GB    | True    |
| 1      | Jan 29, 2026 | 9.68 GB    | True    |
| 1.15.4 | Jan 06, 2026 | 9.57 GB    | True    |
| 1.15.3 | Dec 16, 2025 | 9.57 GB    | True    |
| 1.15.2 | Dec 05, 2025 | 9.57 GB    | True    |
| 1.15.1 | Nov 19, 2025 | 9.61 GB    | True    |
| 1.15.0 | Nov 07, 2025 | 9.61 GB    | True    |
| 1.14.1 | Oct 21, 2025 | 14.03 GB   | True    |
| 1.14   | Oct 21, 2025 | 14.03 GB   | True    |
| 1.14.0 | Sep 18, 2025 | 14.03 GB   | True    |
| 1.13.1 | Aug 28, 2025 | 12.28 GB   | True    |
| 1.13   | Aug 28, 2025 | 12.28 GB   | True    |
| 1.13.0 | Aug 12, 2025 | 13.45 GB   | True    |
| 1.12.0 | Jul 24, 2025 | 12 GB      | True    |
| 1.12   | Jul 24, 2025 | 12 GB      | True    |
| 1.11.0 | Jul 24, 2025 | 10.13 GB   | True    |
| 1.11   | Jul 24, 2025 | 10.13 GB   | True    |
+--------+--------------+------------+---------+
```

If you **don't** have access, you'll get an error or an empty result.

## More Examples

```bash
# NIM images
ngc registry image list nim/nvidia/nv-embedqa-e5-v5
ngc registry image list nim/meta/llama-3.1-8b-instruct

# Standard NVIDIA catalog images
ngc registry image list nvidia/cuda
ngc registry image list nvidia/pytorch
ngc registry image list nvidia/tensorrt

# Wildcard search across a namespace
ngc registry image list nim/nvidia/*
```

## Image Format

The image path follows the pattern: `<org>/[<team>/]<image>[:<tag>]`

| Component | Example |
|-----------|---------|
| org | `nvidia`, `nim` |
| team (optional) | `k8s`, `clara`, `doca` |
| image | `cuda`, `llm-nim`, `nv-embedqa-e5-v5` |
| tag | `12.8.0-base-ubuntu22.04`, `1.15`, `latest` |
