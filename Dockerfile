# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY

# 🔒 Torch nightly cu124 (FP16 fix)
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cu124

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# System deps
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# uv + venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

ENV PATH="/opt/venv/bin:${PATH}"

# Base python tooling
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# --------------------------------------------------------------------
# 🔥 FORCE torch 2.7 nightly + cu124 (EXACT FP16 FIX YOU USED MANUALLY)
# --------------------------------------------------------------------
RUN uv pip install --pre torch --index-url ${PYTORCH_INDEX_URL} \
 && uv pip install --pre torchvision --index-url ${PYTORCH_INDEX_URL} --no-deps

# Sanity check
RUN python - <<'EOF'
import torch
print("torch:", torch.__version__)
print("cuda:", torch.version.cuda)
assert torch.version.cuda == "12.4"
assert hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation")
print("Torch + CUDA OK")
EOF

# ComfyUI paths
WORKDIR /comfyui
ADD src/extra_model_paths.yaml ./

WORKDIR /

# Handler deps
RUN uv pip install runpod requests websocket-client

# --------------------------------------------------------------------
# 📦 APPLICATION FILES
# --------------------------------------------------------------------
ADD src/start.sh \
    src/network_volume.py \
    src/warmup.py \
    src/comfy_client.py \
    src/warmup_workflow.json \
    handler.py \
    test_input.json \
    ./

RUN chmod +x /start.sh

# ComfyUI manager helpers
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

ENV PIP_NO_INPUT=1

CMD ["/start.sh"]


