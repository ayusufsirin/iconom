FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

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
 && apt-get update && apt-get install -y --no-install-recommends \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-pip \
    ros-humble-ros-base \
    ros-humble-cv-bridge \
 && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir "numpy<2" "opencv-python-headless<4.10"
RUN pip3 install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cu118
RUN pip3 install --no-cache-dir ultralytics
RUN pip3 install --no-cache-dir "numpy<2" --force-reinstall

RUN mkdir -p /workspaces
RUN curl -L -o /workspaces/yolov8n.pt https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV ROS_DISTRO=humble
ENV ROS_WS=/workspaces/ros2_ws

WORKDIR /workspaces/ros2_ws

COPY ros2_ws/src/iconom_vision/ /workspaces/ros2_ws/src/iconom_vision/
COPY docker/detector/entrypoint.sh /usr/local/bin/detector-entrypoint.sh

RUN chmod +x /usr/local/bin/detector-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/detector-entrypoint.sh"]
