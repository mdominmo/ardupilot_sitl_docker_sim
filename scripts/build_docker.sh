#!/bin/bash
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE_NAME="ardupilot_sitl_docker_sim"

docker build \
    --build-arg UID=$(id -u) \
    --build-arg GID=$(id -g) \
    -t "$IMAGE_NAME" \
    ../
