#!/bin/bash
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

PIDS=()
SIM_STARTED=false

handle_exit() {
    if ! $SIM_STARTED; then
        return 0
    fi

    echo "Exiting simulation."
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid"
        fi
    done
}

trap handle_exit EXIT

usage() {
    echo "Usage: $0 [--model MODEL] [--vehicles N] [--world WORLD]"
    echo "  Models  : iris (ArduCopter), zephyr (ArduPlane)"
    echo "  WORLD can be provided with or without the .sdf extension"
    echo ""
    echo "GCS connection (per vehicle, instance I starting at 0):"
    echo "  MAVLink TCP : 5760 + I*10"
    echo "  MAVLink UDP : 14550 + I*10"
}

run_cmd() {
    local cmd="$1"
    (eval "$cmd > /dev/null 2>&1" &)
    PIDS+=("$!")
}

run_ardupilot() {
    local cmd="$1"
    local logfile="$2"
    (eval "$cmd > ${logfile} 2>&1" &)
    PIDS+=("$!")
}

# ── Argument parsing ───────────────────────────────────────────────────────────

MODEL="iris"
NUM_VEHICLES=1
WORLD="testbed"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            if [[ -z "$2" ]]; then
                echo "Missing value for --model"
                usage; exit 1
            fi
            MODEL="$2"; shift 2 ;;
        --vehicles|-n)
            if [[ -z "$2" || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "Invalid value for --vehicles: '$2'. Use a positive integer."
                usage; exit 1
            fi
            NUM_VEHICLES="$2"; shift 2 ;;
        --world|-w)
            if [[ -z "$2" ]]; then
                echo "Missing value for --world"
                usage; exit 1
            fi
            WORLD="$2"; shift 2 ;;
        --help|-h)
            usage; exit 0 ;;
        *)
            echo "Unknown argument: $1"
            usage; exit 1 ;;
    esac
done

[[ "$WORLD" == *.sdf ]] && WORLD="${WORLD%.sdf}"

if [[ "$WORLD" == *"/"* ]]; then
    echo "Invalid world '$WORLD'. Use only the world name, not a path."
    usage; exit 1
fi

# ── Model configuration ────────────────────────────────────────────────────────

AP_PATH="$(pwd)/../ardupilot"
AP_GAZEBO_PATH="$(pwd)/../ardupilot_gazebo"

case "$MODEL" in
    iris)
        AP_BINARY="${AP_PATH}/build/sitl/bin/arducopter"
        AP_FRAME="gazebo-iris"
        MODEL_SDF="${AP_GAZEBO_PATH}/models/iris_with_ardupilot/model.sdf"
        ;;
    zephyr)
        AP_BINARY="${AP_PATH}/build/sitl/bin/arduplane"
        AP_FRAME="gazebo-zephyr"
        MODEL_SDF="${AP_GAZEBO_PATH}/models/zephyr_with_ardupilot/model.sdf"
        ;;
    *)
        echo "Unknown model: $MODEL"
        usage; exit 1 ;;
esac

DEFAULTS_FILE="${AP_PATH}/Tools/autotest/default_params/${AP_FRAME}.parm"

if [[ ! -f "$AP_BINARY" ]]; then
    echo "ArduPilot binary not found: $AP_BINARY"
    echo "The image may not have built correctly."
    exit 1
fi

if [[ ! -f "$MODEL_SDF" ]]; then
    echo "Model SDF not found: $MODEL_SDF"
    exit 1
fi

# ── World validation ───────────────────────────────────────────────────────────
# Search order: gz_assets/worlds/ first, then ardupilot_gazebo/worlds/

WORLD_FILE=""
for dir in \
    "$(pwd)/../gz_assets/worlds" \
    "${AP_GAZEBO_PATH}/worlds"
do
    if [[ -f "${dir}/${WORLD}.sdf" ]]; then
        WORLD_FILE="${dir}/${WORLD}.sdf"
        break
    fi
done

if [[ -z "$WORLD_FILE" ]]; then
    echo "World not found: $WORLD"
    echo "Available worlds:"
    shopt -s nullglob
    for dir in "$(pwd)/../gz_assets/worlds" "${AP_GAZEBO_PATH}/worlds"; do
        for f in "${dir}"/*.sdf; do
            echo "  - $(basename "$f" .sdf)"
        done
    done
    shopt -u nullglob
    exit 1
fi

# ── Pre-spawned world detection ────────────────────────────────────────────────
# ardupilot_gazebo worlds (iris_runway, zephyr_runway, gimbal) already embed
# one vehicle with fdm_port_in=9002. Using --vehicles > 1 with these worlds
# would conflict on port 9002 for the pre-spawned model.
ARDUPILOT_GZ_WORLDS=("iris_runway" "zephyr_runway" "gimbal")
IS_PRESPAWNED_WORLD=false
for w in "${ARDUPILOT_GZ_WORLDS[@]}"; do
    [[ "$WORLD" == "$w" ]] && IS_PRESPAWNED_WORLD=true && break
done

if $IS_PRESPAWNED_WORLD && [[ $NUM_VEHICLES -gt 1 ]]; then
    echo "World '$WORLD' has a pre-spawned vehicle on port 9002."
    echo "Multi-vehicle is only supported with worlds that have no pre-spawned vehicles (e.g. testbed)."
    exit 1
fi

echo "Setting up the simulation environment..."
echo "  Model    : $MODEL"
echo "  Vehicles : $NUM_VEHICLES"
echo "  World    : $WORLD"

# ── Start Gazebo ───────────────────────────────────────────────────────────────
echo "Starting Gazebo... (log: /tmp/gazebo.log)"
SIM_STARTED=true
run_ardupilot "gz sim -r ${WORLD_FILE}" "/tmp/gazebo.log"
sleep 15

# ── Spawn vehicles ─────────────────────────────────────────────────────────────
# For pre-spawned worlds (iris_runway etc.): vehicle 0 is already in the world,
# just launch ArduPilot SITL and it will connect on the default port (9002).
#
# For custom worlds (testbed etc.): spawn all vehicles dynamically via gz service.
# Each instance uses fdm_port_in = 9002 + I*10 (where I = vehicle index, 0-based).
# ArduPilot with -I I automatically connects to this port.

y_0="0"

for ((vehicle=1; vehicle<=NUM_VEHICLES; vehicle++)); do
    instance=$((vehicle - 1))
    port=$((9002 + instance * 10))
    y_pos=$((y_0 - instance * 2))

    if ! $IS_PRESPAWNED_WORLD; then
        TEMP_SDF="/tmp/${MODEL}_instance_${instance}.sdf"
        sed "s|<fdm_port_in>9002</fdm_port_in>|<fdm_port_in>${port}</fdm_port_in>|g" \
            "$MODEL_SDF" > "$TEMP_SDF"

        SPAWN_Z="0.3"
        if [[ "$MODEL" == "iris" ]]; then
            # Match the official iris_runway spawn height.
            SPAWN_Z="0.195"
        fi

        echo "Spawning ${MODEL}_${instance} at y=${y_pos} z=${SPAWN_Z} on port ${port}..."
        SPAWN_RESULT=$(gz service -s "/world/${WORLD}/create" \
            --reqtype gz.msgs.EntityFactory \
            --reptype gz.msgs.Boolean \
            --timeout 5000 \
            --req "sdf_filename: \"${TEMP_SDF}\" \
                   name: \"${MODEL}_${instance}\" \
                   pose { position { x: 0.0 y: ${y_pos}.0 z: ${SPAWN_Z} } }" 2>&1)
        echo "  Spawn result: ${SPAWN_RESULT}"
        sleep 5
    fi

    echo "Starting ArduPilot SITL instance ${instance} (MAVLink TCP: $((5760 + instance * 10)), UDP: $((14550 + instance * 10)))..."

    DEFAULTS_FLAG=""
    [[ -f "$DEFAULTS_FILE" ]] && DEFAULTS_FLAG="--defaults ${DEFAULTS_FILE}"

    AP_LOG="/tmp/ardupilot_instance_${instance}.log"
    echo "  ArduPilot log: ${AP_LOG}"

    run_ardupilot "${AP_BINARY} \
        --model JSON \
        --speedup 1 \
        --home 52.11486,-6.613,2,270 \
        ${DEFAULTS_FLAG} \
        -I ${instance}" \
        "${AP_LOG}"

    # Wait for ArduPilot to finish booting, then start MAVProxy as relay:
    # TCP 5760 (mixed console+MAVLink) → UDP 14550 (pure MAVLink for QGC/MAVSDK)
    TCP_PORT=$((5760 + instance * 10))
    UDP_OUT=$((14550 + instance * 10))
    MVP_LOG="/tmp/mavproxy_${instance}.log"
    echo "  MAVProxy relay: TCP ${TCP_PORT} → UDP ${UDP_OUT} (log: ${MVP_LOG})"
    sleep 20
    MAVSDK_PORT=$((14570 + instance * 10))
    run_ardupilot "mavproxy.py \
        --master=tcp:127.0.0.1:${TCP_PORT} \
        --out=udp:127.0.0.1:${UDP_OUT} \
        --out=tcpin:0.0.0.0:${MAVSDK_PORT} \
        --non-interactive" \
        "${MVP_LOG}"

    sleep 2
done

echo "Simulation started."
while true; do
    sleep 5
done
