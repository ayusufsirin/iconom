FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG PX4_GIT_REF=v1.16.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    python3 \
    python3-pip \
    sudo \
    wget \
 && curl -sSL http://packages.osrfoundation.org/gazebo.key \
    | gpg --dearmor -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(. /etc/os-release && echo ${UBUNTU_CODENAME}) main" \
    > /etc/apt/sources.list.d/gazebo-stable.list \
 && apt-get update && apt-get install -y --no-install-recommends \
    gz-harmonic \
    libopencv-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone --branch "${PX4_GIT_REF}" --depth 1 --recursive https://github.com/PX4/PX4-Autopilot.git

WORKDIR /opt/PX4-Autopilot

RUN bash ./Tools/setup/ubuntu.sh --no-sim-tools --no-nuttx \
 && make px4_sitl_default

COPY docker/px4/entrypoint.sh /usr/local/bin/px4-entrypoint.sh
COPY docker/px4/run-single-vehicle.sh /usr/local/bin/px4-run-single-vehicle.sh

RUN chmod +x /usr/local/bin/px4-entrypoint.sh /usr/local/bin/px4-run-single-vehicle.sh

ENV PX4_HOME=/opt/PX4-Autopilot
ENV PX4_GIT_REF=v1.16.0
ENV GZ_VERSION=harmonic
ENV PX4_HEADLESS=1
ENV PX4_SYS_AUTOSTART=4003
ENV PX4_GZ_WORLD=default
ENV PX4_UXRCE_DDS_NS=plane_01
ENV UXRCE_DDS_KEY=1
ENV XRCE_AGENT_UDP_PORT=8888
ENV MAVLINK_OFFBOARD_BASE_PORT=14540
ENV MAVLINK_GCS_PORT=14550
ENV PX4_SIM_MODEL=gz_rc_cessna

WORKDIR /opt/PX4-Autopilot

ENTRYPOINT ["/usr/local/bin/px4-entrypoint.sh"]
