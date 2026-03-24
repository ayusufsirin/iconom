FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    locales \
 && locale-gen en_US en_US.UTF-8 \
 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
 && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME}) main" \
    > /etc/apt/sources.list.d/ros2.list \
 && apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-vcstool \
    python3-pip \
    ros-humble-ros-base \
 && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir requests

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV ROS_DISTRO=humble
ENV ROS_WS=/workspaces/ros2_ws

WORKDIR /workspaces/ros2_ws

COPY ros2_ws/ /workspaces/ros2_ws/
COPY docker/ros2_app/entrypoint.sh /usr/local/bin/ros2-app-entrypoint.sh

RUN chmod +x /usr/local/bin/ros2-app-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ros2-app-entrypoint.sh"]
CMD ["bash", "-lc", "echo 'ros2_app base workspace ready; no project packages are implemented yet'; sleep infinity"]
