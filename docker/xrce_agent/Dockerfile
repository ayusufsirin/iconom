FROM ubuntu:22.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG XRCE_AGENT_VERSION=v2.4.3

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    git \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --branch "${XRCE_AGENT_VERSION}" --depth 1 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git

WORKDIR /src/Micro-XRCE-DDS-Agent

RUN cmake -B build -S . \
 && cmake --build build --parallel \
 && cmake --install build --prefix /opt/microxrce

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/microxrce /opt/microxrce
COPY docker/xrce_agent/entrypoint.sh /usr/local/bin/xrce-agent-entrypoint.sh

RUN chmod +x /usr/local/bin/xrce-agent-entrypoint.sh

ENV XRCE_AGENT_UDP_PORT=8888

EXPOSE 8888/udp

ENTRYPOINT ["/usr/local/bin/xrce-agent-entrypoint.sh"]
