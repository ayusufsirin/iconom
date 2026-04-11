FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    locales \
 && locale-gen en_US en_US.UTF-8 \
 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
 && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME}) main" \
    > /etc/apt/sources.list.d/ros2.list \
 && curl -sSL http://packages.osrfoundation.org/gazebo.key \
    | gpg --dearmor -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(. /etc/os-release && echo ${UBUNTU_CODENAME}) main" \
    > /etc/apt/sources.list.d/gazebo-stable.list \
 && apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-ros-base \
    ros-humble-ros-gzharmonic \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV ROS_DISTRO=humble
ENV GZ_VERSION=harmonic
ENV GZ_SIM_RESOURCE_PATH=/opt/iconom/sim
ENV GAZEBO_WORLD_FILE=/opt/iconom/sim/worlds/empty.sdf

WORKDIR /opt/iconom/sim

COPY sim/ /opt/iconom/sim/
COPY docker/gazebo/entrypoint.sh /usr/local/bin/gazebo-entrypoint.sh
COPY docker/ros_gz_bridge/entrypoint.sh /usr/local/bin/ros-gz-bridge-entrypoint.sh
COPY docker/ros_gz_bridge/pose_bridge_entrypoint.sh /usr/local/bin/pose-bridge-entrypoint.sh
COPY sim/bridge.yaml /opt/iconom/sim/bridge.yaml

RUN chmod +x /usr/local/bin/gazebo-entrypoint.sh /usr/local/bin/ros-gz-bridge-entrypoint.sh /usr/local/bin/pose-bridge-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/gazebo-entrypoint.sh"]
CMD ["/usr/local/bin/ros-gz-bridge-entrypoint.sh"]
