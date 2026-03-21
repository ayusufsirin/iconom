FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG PX4_GIT_REF=v1.16.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
 && curl -sSL http://packages.osrfoundation.org/gazebo.key \
    | gpg --dearmor -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(. /etc/os-release && echo ${UBUNTU_CODENAME}) main" \
    > /etc/apt/sources.list.d/gazebo-stable.list \
 && apt-get update && apt-get install -y --no-install-recommends \
    gz-launch7-cli \
    gz-sim8-cli \
    gz-tools2 \
    libgz-physics7-dartsim \
    libgz-sim8 \
    libgz-sim8-plugins \
 && rm -rf /var/lib/apt/lists/*

ENV GZ_VERSION=harmonic
ENV GZ_SIM_PHYSICS_ENGINE_PATH=/usr/lib/x86_64-linux-gnu/gz-physics-7/engine-plugins
ENV GZ_SIM_RESOURCE_PATH=/opt/iconom/sim:/opt/PX4-Autopilot/Tools/simulation/gz/models:/opt/PX4-Autopilot/Tools/simulation/gz/worlds
ENV GAZEBO_WORLD_FILE=/opt/PX4-Autopilot/Tools/simulation/gz/worlds/default.sdf

WORKDIR /opt/iconom/sim

RUN git clone --branch "${PX4_GIT_REF}" --depth 1 https://github.com/PX4/PX4-Autopilot.git /opt/PX4-Autopilot \
 && git -C /opt/PX4-Autopilot submodule update --init --depth 1 Tools/simulation/gz

COPY sim/ /opt/iconom/sim/
COPY docker/gazebo/entrypoint.sh /usr/local/bin/gazebo-entrypoint.sh

RUN ln -sf /usr/lib/x86_64-linux-gnu/gz-physics-7/engine-plugins/libgz-physics7-dartsim-plugin.so.7 \
      /usr/lib/x86_64-linux-gnu/gz-physics-7/engine-plugins/libgz-physics-dartsim-plugin.so \
 && chmod +x /usr/local/bin/gazebo-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/gazebo-entrypoint.sh"]
CMD ["bash", "-lc", "gz sim -s -r \"${GAZEBO_WORLD_FILE}\""]
