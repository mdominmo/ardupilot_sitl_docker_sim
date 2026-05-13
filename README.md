# ArduPilot SITL Docker Sim
![GitHub tag](https://img.shields.io/github/v/tag/mdominmo/ardupilot_sitl_docker_sim)
![GitHub](https://img.shields.io/github/license/mdominmo/ardupilot_sitl_docker_sim)

Built for fast robotics development, the simulator connects seamlessly through MAVROS, MAVSDK, and MAVLink-compatible ground control stations.

`ardupilot_sitl_docker_sim` is a tool to run ArduPilot SITL with Gazebo Harmonic through Docker, using the NVIDIA Container Toolkit to take advantage of NVIDIA GPU acceleration.

The main strength of this project is that developers do not need to manage the manual installation of ArduPilot, its dependencies, or the `ardupilot_gazebo` plugin on the host machine.

## What You Get

- ArduPilot SITL environment inside Docker (pinned to Copter-4.6.3)
- Gazebo Harmonic preinstalled with the `ardupilot_gazebo` plugin
- ROS 2 Humble with MAVROS available in the container
- MAVProxy relay included for GCS and MAVSDK connectivity
- GPU rendering support with NVIDIA

## Requirements

- Linux with Docker installed
- NVIDIA GPU + NVIDIA drivers
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- X11 access for GUI simulation

## Quick Start

1. Build the Docker image:

```bash
./scripts/build_docker.sh
```

2. Run the simulator (default: `iris` model, 1 vehicle, `testbed` world):

```bash
./scripts/run_docker.sh
```

3. Run with custom options:

```bash
./scripts/run_docker.sh --model iris --vehicles 2 --world testbed
```

## Runtime Options

- `--model` or `-m`: `iris` (ArduCopter) | `zephyr` (ArduPlane)
- `--vehicles` or `-n`: number of vehicles to spawn (only supported with worlds that have no pre-spawned vehicles)
- `--world` or `-w`: world name (with or without `.sdf`)
- Default: `iris`, 1 vehicle, `testbed` world
- If the selected world does not exist, the launcher returns an error with all available world names

### Available Worlds

| World | Source | Pre-spawned vehicle |
|---|---|---|
| `testbed` | `gz_assets/worlds/` | No |
| `iris_runway` | `ardupilot_gazebo` | Yes (iris) |
| `zephyr_runway` | `ardupilot_gazebo` | Yes (zephyr) |
| `gimbal` | `ardupilot_gazebo` | Yes (iris) |

Worlds in `gz_assets/worlds/` take search priority over `ardupilot_gazebo/worlds/`.

Pre-spawned worlds (`iris_runway`, `zephyr_runway`, `gimbal`) only support a single vehicle.

## GCS Connection

MAVProxy is launched as a relay for each vehicle. Per vehicle instance `I` (starting at 0):

| Interface | Address |
|---|---|
| MAVLink TCP (ArduPilot raw) | `tcp://localhost:$((5760 + I*10))` |
| MAVLink UDP (QGroundControl) | `udp://localhost:$((14550 + I*10))` |
| MAVLink TCP (MAVSDK) | `tcpin://localhost:$((14570 + I*10))` |

## Custom Models And Worlds

You can add your own assets without changing the scripts:

- Add new worlds in `gz_assets/worlds/<your_world_name>.sdf`
- Add new models in `gz_assets/models/<your_model_name>/...`

Then run the simulator using the new world:

```bash
./scripts/run_docker.sh --world <your_world_name>
```

`run_docker.sh` mounts `gz_assets/models` and `gz_assets/worlds` as volumes, so your local assets are used directly by Gazebo.
