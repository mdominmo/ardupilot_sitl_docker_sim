#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="ardupilot_sitl_docker_sim"

xhost +local:docker

docker run -it --rm \
    --network host \
    --ipc=host \
    --gpus all \
    -e DISPLAY=$DISPLAY \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e __NV_PRIME_RENDER_OFFLOAD=1 \
    -e __GLX_VENDOR_LIBRARY_NAME=nvidia \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "$HOME/.Xauthority:/home/dev/.Xauthority:ro" \
    -v "$REPO_ROOT/gz_assets/models:/workspace/ardupilot_sitl_docker_sim/gz_assets/models" \
    -v "$REPO_ROOT/gz_assets/worlds:/workspace/ardupilot_sitl_docker_sim/gz_assets/worlds" \
    "$IMAGE_NAME" "$@"
