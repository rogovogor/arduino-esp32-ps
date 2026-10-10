# Build environment: the official ESP-IDF 4.4.7 image plus what the
# esp32-arduino-lib-builder scripts expect. The image tag is pinned in versions.env.
ARG IDF_DOCKER_IMAGE=espressif/idf:v4.4.7
FROM ${IDF_DOCKER_IMAGE}

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git curl jq xz-utils ca-certificates rsync \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
# The repository is mounted at /work; scripts/build-libs.sh does the rest.
ENTRYPOINT ["/opt/esp/entrypoint.sh"]
CMD ["bash", "scripts/build-libs.sh"]
