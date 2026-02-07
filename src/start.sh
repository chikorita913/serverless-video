#!/usr/bin/env bash
set -euo pipefail

TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1 || true)"
if [ -n "${TCMALLOC}" ]; then
  export LD_PRELOAD="${TCMALLOC}"
fi

comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo "worker-comfyui: Starting ComfyUI"
: "${COMFY_LOG_LEVEL:=DEBUG}"

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

if [ ! -f /warmup_workflow.json ]; then
  echo "ERROR: /warmup_workflow.json missing. Extend this base image and COPY warmup_workflow.json to /warmup_workflow.json" >&2
  exit 1
fi

python -u /warmup.py

echo "worker-comfyui: Starting RunPod Handler"
if [ "${SERVE_API_LOCALLY:-false}" == "true" ]; then
  python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
  python -u /handler.py
fi
