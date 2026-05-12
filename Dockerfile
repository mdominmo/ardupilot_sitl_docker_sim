FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

ARG UID=1000
ARG GID=1000
ARG USERNAME=dev

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Madrid
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all
ENV GZ_VERSION=harmonic

# ── Timezone ───────────────────────────────────────────────────────────────────
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ── Base system packages ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo curl git zip unzip wget cmake build-essential \
        lsb-release software-properties-common gnupg ca-certificates \
        locales python3 python3-pip python-is-python3 \
        libx11-6 libxext6 libxrender1 libxtst6 libxi6 libxrandr2 \
        libxcursor1 libxcomposite1 libxdamage1 libxfixes3 libxss1 \
        libasound2 libpulse0 libgl1-mesa-glx libgl1-mesa-dri \
        libegl1 libglu1-mesa x11-apps mesa-utils libfuse2 \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ── Gazebo Harmonic (from osrfoundation) ──────────────────────────────────────
# Installed before ROS2 and ArduPilot as the single Gazebo source.
# libgz-sim8-dev is required for the ardupilot_gazebo plugin build.
RUN wget https://packages.osrfoundation.org/gazebo.gpg \
       -O /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] \
       http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
       | tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends \
       gz-harmonic \
       libgz-sim8-dev \
       libgz-transport13-dev \
       python3-gz-transport13 \
       rapidjson-dev \
       libopencv-dev \
       libgstreamer1.0-dev \
       libgstreamer-plugins-base1.0-dev \
       gstreamer1.0-plugins-bad \
       gstreamer1.0-libav \
       gstreamer1.0-gl \
    && rm -rf /var/lib/apt/lists/*

# ── ROS2 Humble ────────────────────────────────────────────────────────────────
RUN mkdir -p /etc/apt/keyrings \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
       | gpg --dearmor -o /etc/apt/keyrings/ros-archive-keyring.gpg \
    && add-apt-repository universe \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] \
       http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
       | tee /etc/apt/sources.list.d/ros2.list > /dev/null \
    && apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
       ros-humble-desktop \
       ros-dev-tools \
       ros-humble-ament-cmake \
       ros-humble-geographic-msgs \
       ros-humble-mavros \
       ros-humble-mavros-extras \
    && (/opt/ros/humble/bin/ros2 run mavros install_geographiclib_datasets.sh || true) \
    && rm -rf /var/lib/apt/lists/*

# ── User setup ─────────────────────────────────────────────────────────────────
# Created here (before ArduPilot clone) because install-prereqs-ubuntu.sh
# explicitly rejects root (exits 1 if EUID==0). The script runs as this user
# and uses sudo internally for apt/pip installs.
RUN groupadd -g ${GID} ${USERNAME} \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
    && usermod -aG video ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── ArduPilot clone (root) ─────────────────────────────────────────────────────
# Pinned to Copter-4.6.3. The monorepo contains all vehicle types:
# waf copter → arducopter,  waf plane → arduplane
WORKDIR /workspace/ardupilot_sitl_docker_sim

RUN git clone \
        --branch Copter-4.6.3 \
        --depth 1 \
        --recurse-submodules \
        https://github.com/ArduPilot/ardupilot.git \
    && chown -R ${USERNAME}:${USERNAME} /workspace

# ── ArduPilot install + build (user) ──────────────────────────────────────────
# install-prereqs-ubuntu.sh rejects root AND uses $USER for `usermod -a -G dialout $USER`.
# Docker's USER instruction changes the UID but does not export $USER to the environment,
# so we set it explicitly here.
ENV USER=${USERNAME}
USER ${USERNAME}

RUN ardupilot/Tools/environment_install/install-prereqs-ubuntu.sh -y \
    && sudo rm -rf /var/lib/apt/lists/*

RUN cd ardupilot \
    && ./waf configure --board sitl \
    && ./waf copter \
    && ./waf plane

# ── ardupilot_gazebo plugin (root) ────────────────────────────────────────────
# Provides ArduPilotPlugin for Gazebo Harmonic. Communicates with ArduPilot
# SITL via JSON over UDP (fdm_port_in). GZ_VERSION=harmonic is picked up by
# cmake to select the correct gz-sim8 package.
USER root

RUN git clone \
        --depth 1 \
        https://github.com/ArduPilot/ardupilot_gazebo.git

RUN cd ardupilot_gazebo \
    && mkdir build && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    && make -j"$(nproc)"

# ── Plugin and resource paths ──────────────────────────────────────────────────
# GZ_SIM_SYSTEM_PLUGIN_PATH: where Gazebo finds the ArduPilotPlugin .so
# GZ_SIM_RESOURCE_PATH: where Gazebo resolves model:// and world:// URIs.
#   Includes both ardupilot_gazebo assets and user-mounted gz_assets.
ENV GZ_SIM_SYSTEM_PLUGIN_PATH=/workspace/ardupilot_sitl_docker_sim/ardupilot_gazebo/build
ENV GZ_SIM_RESOURCE_PATH=/workspace/ardupilot_sitl_docker_sim/ardupilot_gazebo/models:/workspace/ardupilot_sitl_docker_sim/ardupilot_gazebo/worlds:/workspace/ardupilot_sitl_docker_sim/gz_assets/models:/workspace/ardupilot_sitl_docker_sim/gz_assets/worlds

# ── Copy project files ─────────────────────────────────────────────────────────
# ardupilot/, ardupilot_gazebo/ and gz_assets/ are excluded via .dockerignore
COPY . /workspace/ardupilot_sitl_docker_sim/

# ── Permissions & ROS2 sourcing ────────────────────────────────────────────────
RUN chown -R ${USERNAME}:${USERNAME} /workspace \
    && chmod +x scripts/launch_simulator.sh \
               scripts/entrypoint.sh \
    && echo 'source /opt/ros/humble/setup.bash' >> /etc/bash.bashrc

USER ${USERNAME}
WORKDIR /workspace/ardupilot_sitl_docker_sim

RUN echo 'source /opt/ros/humble/setup.bash' >> ~/.bashrc

# Default: iris (ArduCopter), 1 vehicle in testbed world.
# Override with: docker run ... ardupilot_sitl_docker_sim --model iris|zephyr --vehicles N --world WORLD
CMD ["--model", "iris", "--vehicles", "1"]
ENTRYPOINT ["/workspace/ardupilot_sitl_docker_sim/scripts/entrypoint.sh"]
