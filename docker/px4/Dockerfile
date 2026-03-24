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
    libgstreamer-plugins-base1.0-dev \
    libgstreamer1.0-dev \
    libopencv-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone --branch "${PX4_GIT_REF}" --depth 1 --recursive https://github.com/PX4/PX4-Autopilot.git

WORKDIR /opt/PX4-Autopilot

RUN python3 - <<'PY'
from pathlib import Path

path = Path("/opt/PX4-Autopilot/ROMFS/px4fmu_common/init.d-posix/rcS")
old = "uxrce_dds_client start -t udp -h 127.0.0.1 -p $uxrce_dds_port $uxrce_dds_ns"
new = "uxrce_dds_client start -t udp -h ${PX4_UXRCE_DDS_HOST:-127.0.0.1} -p $uxrce_dds_port $uxrce_dds_ns"
text = path.read_text()

if old not in text:
    raise SystemExit(f"expected rcS line not found in {path}")

path.write_text(text.replace(old, new, 1))
PY

RUN grep -n '\${PX4_UXRCE_DDS_HOST:-127.0.0.1}' /opt/PX4-Autopilot/ROMFS/px4fmu_common/init.d-posix/rcS

RUN python3 - <<'PY'
from pathlib import Path

path = Path("/opt/PX4-Autopilot/Tools/simulation/gz/models/rc_cessna/model.sdf")
anchor = "    <link name=\"airspeed\">"
insert = """    <include merge='true'>\n      <uri>model://mono_cam</uri>\n      <pose>0.24 0 0.02 0 0 0</pose>\n    </include>\n    <joint name=\"camera_joint\" type=\"fixed\">\n      <parent>base_link</parent>\n      <child>camera_link</child>\n      <pose relative_to=\"base_link\">0.24 0 0.02 0 0 0</pose>\n    </joint>\n    <link name=\"airspeed\">"""
text = path.read_text()

if anchor not in text:
    raise SystemExit(f"expected rc_cessna insertion point not found in {path}")

path.write_text(text.replace(anchor, insert, 1))
PY

RUN grep -n 'model://mono_cam' /opt/PX4-Autopilot/Tools/simulation/gz/models/rc_cessna/model.sdf \
 && grep -n 'camera_joint' /opt/PX4-Autopilot/Tools/simulation/gz/models/rc_cessna/model.sdf

RUN python3 - <<'PY'
from pathlib import Path

path = Path("/opt/PX4-Autopilot/ROMFS/px4fmu_common/init.d-posix/airframes/4003_gz_rc_cessna")
text = path.read_text()

if "param set-default NAV_DLL_ACT 2" not in text:
    raise SystemExit(f"expected NAV_DLL_ACT default not found in {path}")

text = text.replace("param set-default NAV_DLL_ACT 2", "param set-default NAV_DLL_ACT 0", 1)

anchor = "param set-default SENS_EN_ARSPDSIM 1\n"
insert = "param set-default SENS_EN_ARSPDSIM 1\nparam set-default SYS_HAS_NUM_ASPD 0\n"

if anchor not in text:
    raise SystemExit(f"expected airspeed insertion point not found in {path}")

text = text.replace(anchor, insert, 1)
path.write_text(text)
PY

RUN grep -n 'SYS_HAS_NUM_ASPD' /opt/PX4-Autopilot/ROMFS/px4fmu_common/init.d-posix/airframes/4003_gz_rc_cessna \
 && grep -n 'NAV_DLL_ACT' /opt/PX4-Autopilot/ROMFS/px4fmu_common/init.d-posix/airframes/4003_gz_rc_cessna

RUN python3 - <<'PY'
from pathlib import Path

path = Path("/opt/PX4-Autopilot/src/modules/simulation/gz_bridge/CMakeLists.txt")
text = path.read_text()
old_default = "COMMAND ${CMAKE_COMMAND} -E env PX4_SIM_MODEL=gz_${model_name} GZ_IP=127.0.0.1 $<TARGET_FILE:px4>"
new_default = "COMMAND ${CMAKE_COMMAND} -E env PX4_SIM_MODEL=gz_${model_name} GZ_IP=$$GZ_IP $<TARGET_FILE:px4>"
old_world = "COMMAND ${CMAKE_COMMAND} -E env PX4_SIM_MODEL=gz_${model_name} PX4_GZ_WORLD=${world_name} GZ_IP=127.0.0.1 $<TARGET_FILE:px4>"
new_world = "COMMAND ${CMAKE_COMMAND} -E env PX4_SIM_MODEL=gz_${model_name} PX4_GZ_WORLD=${world_name} GZ_IP=$$GZ_IP $<TARGET_FILE:px4>"

if old_default not in text or old_world not in text:
    raise SystemExit(f"expected gz_bridge CMake launch lines not found in {path}")

text = text.replace(old_default, new_default, 1).replace(old_world, new_world, 1)
path.write_text(text)
PY

RUN grep -n '\$\$GZ_IP' /opt/PX4-Autopilot/src/modules/simulation/gz_bridge/CMakeLists.txt

RUN bash ./Tools/setup/ubuntu.sh --no-sim-tools --no-nuttx \
 && make px4_sitl_default

COPY docker/px4/entrypoint.sh /usr/local/bin/px4-entrypoint.sh
COPY docker/px4/run-vehicle.sh /usr/local/bin/px4-run-vehicle.sh
COPY docker/px4/run-single-vehicle.sh /usr/local/bin/px4-run-single-vehicle.sh

RUN chmod +x /usr/local/bin/px4-entrypoint.sh /usr/local/bin/px4-run-vehicle.sh /usr/local/bin/px4-run-single-vehicle.sh

ENV PX4_HOME=/opt/PX4-Autopilot
ENV PX4_GIT_REF=v1.16.0
ENV GZ_VERSION=harmonic
ENV PX4_HEADLESS=1
ENV PX4_SYS_AUTOSTART=4003
ENV PX4_GZ_WORLD=default
ENV PX4_UXRCE_DDS_HOST=xrce_agent
ENV PX4_UXRCE_DDS_NS=plane_01
ENV UXRCE_DDS_KEY=1
ENV XRCE_AGENT_UDP_PORT=8888
ENV MAVLINK_OFFBOARD_BASE_PORT=14540
ENV MAVLINK_GCS_PORT=14550
ENV PX4_SIM_MODEL=gz_rc_cessna
ENV PX4_INSTANCE=0
ENV PX4_GZ_MODEL_POSE=0,0,0
ENV ICONOM_GZ_MODEL_NAME=rc_cessna_0
ENV ICONOM_EXPECTED_MAV_SYS_ID=1
ENV ICONOM_EXPECTED_MAVLINK_OFFBOARD_PORT=14540

WORKDIR /opt/PX4-Autopilot

ENTRYPOINT ["/usr/local/bin/px4-entrypoint.sh"]
