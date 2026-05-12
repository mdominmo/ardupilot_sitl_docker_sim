#!/bin/bash
set -e

source /opt/ros/humble/setup.bash
export PATH=$PATH:/home/dev/.local/bin

exec /workspace/ardupilot_sitl_docker_sim/scripts/launch_simulator.sh "$@"
