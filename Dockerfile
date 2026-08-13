# Use an official ggml-org/llama.cpp image as the base image.
# NOTE: keep the rolling "server-cuda" tag (built from latest master, CUDA 12.x / 12.8.1).
# The "-bXXXX" build tags can be stale and miss recent features (e.g. multimodal --mmproj).
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

ENV PYTHONUNBUFFERED=1

# Set up the working directory
WORKDIR /

RUN apt-get update --yes --quiet && DEBIAN_FRONTEND=noninteractive apt-get install --yes --quiet --no-install-recommends \
    software-properties-common \
    gpg-agent \
    build-essential apt-utils \
    && apt-get install --reinstall ca-certificates \
    && add-apt-repository --yes ppa:deadsnakes/ppa && apt update --yes --quiet \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --quiet --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3.11-distutils \
    python3.11-lib2to3 \
    python3.11-gdbm \
    python3.11-tk \
    bash \
    curl && \
    ln -s /usr/bin/python3.11 /usr/bin/python && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /work

# Add ./src as /work
ADD ./src /work

# Install runpod and its dependencies
# --ignore-installed avoids the "uninstall-no-record-file" error on the
# Debian-provided cryptography package present in the base image.
RUN python -m pip install --break-system-packages --ignore-installed -r ./requirements.txt && chmod +x /work/start.sh

# Set the entrypoint
ENTRYPOINT ["/bin/sh", "-c", "/work/start.sh"]