# The capture renderer: a Linux arm64 box with a virtual display and a software
# Vulkan driver, so an agent's screenshot renders off the developer's desktop
# instead of flashing a window across it (COM-279).
#
# Native linux/arm64 — no x86 emulation. The engine is the official Linux arm64
# build of the same version the macOS binary is; the image tag carries that
# version, so a bump is a different image and cannot be answered from cache.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.1-stable

# xvfb is the display and Mesa is the renderer: llvmpipe (libgl1-mesa-dri) draws
# for the project's gl_compatibility method, lavapipe (mesa-vulkan-drivers) is
# there for the Vulkan one. The x11 libraries are what the engine links against
# at startup, and fontconfig is what it finds a fallback face through — without
# it every glyph the project does not ship a font for is a box. No ALSA: there
# is no sound card here, and the engine falls back to its dummy audio driver.
RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates \
	curl \
	fontconfig \
	fonts-dejavu-core \
	libdbus-1-3 \
	libgl1 \
	libgl1-mesa-dri \
	libvulkan1 \
	libx11-6 \
	libxcursor1 \
	libxext6 \
	libxi6 \
	libxinerama1 \
	libxkbcommon0 \
	libxrandr2 \
	mesa-vulkan-drivers \
	unzip \
	xauth \
	xvfb \
	&& rm -rf /var/lib/apt/lists/*

RUN url="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.arm64.zip" \
	&& curl -sSfL -o /tmp/godot.zip "$url" \
	&& unzip -q /tmp/godot.zip -d /tmp/godot \
	&& mv "/tmp/godot/Godot_v${GODOT_VERSION}_linux.arm64" /usr/local/bin/godot \
	&& chmod +x /usr/local/bin/godot \
	&& rm -rf /tmp/godot.zip /tmp/godot

COPY entrypoint.sh /usr/local/bin/capture-entrypoint
RUN chmod +x /usr/local/bin/capture-entrypoint

ENTRYPOINT ["/usr/local/bin/capture-entrypoint"]
