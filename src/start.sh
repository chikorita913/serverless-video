#!/usr/bin/env bash
set -euo pipefail

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1 || true)"
if [ -n "${TCMALLOC}" ]; then
  export LD_PRELOAD="${TCMALLOC}"
fi

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
if [ "${SERVE_API_LOCALLY:-false}" == "true" ]; then
  python -u /comfyui/main.py \
      --disable-auto-launch \
      --disable-metadata \
      --listen \
      --verbose "${COMFY_LOG_LEVEL}" \
      --log-stdout &
else
  python -u /comfyui/main.py \
      --disable-auto-launch \
      --disable-metadata \
      --verbose "${COMFY_LOG_LEVEL}" \
      --log-stdout &
fi

# 🔥 WARMUP WORKFLOW MUST BE PROVIDED BY DOWNSTREAM IMAGE
if [ ! -f /warmup_workflow.json ]; then
  echo "ERROR: /warmup_workflow.json missing. This base image must be extended by an endpoint image that copies it to /warmup_workflow.json" >&2
  exit 1
fi

# 🔥 WARMUP (brick worker on failure)
python -u /warmup.py

echo "worker-comfyui: Starting RunPod Handler"
if [ "${SERVE_API_LOCALLY:-false}" == "true" ]; then
  python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
  python -u /handler.py
fi
