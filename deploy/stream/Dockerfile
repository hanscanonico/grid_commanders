# The 24/7 Twitch stream: the game playing itself on a virtual screen, drawn by the
# host's Intel GPU, encoded and sent out. The 3D board manages 1-4 fps on Mesa's
# software renderer here, so the GPU is required, not an optimisation.
#
# Xvfb has no GPU of its own. VirtualGL gives the game's OpenGL calls to the GPU
# through EGL and copies each finished frame onto the virtual screen.
FROM barichello/godot-ci:4.7.1 AS game
WORKDIR /game
COPY . .
RUN godot --headless --path . --import

FROM debian:trixie-slim
ADD --checksum=sha256:df3f7788ce41b182a47c0d298e5cd6d2d63579522cb41825970b7726e825485e \
	https://github.com/VirtualGL/virtualgl/releases/download/3.1.5/virtualgl_3.1.5_amd64.deb \
	/tmp/virtualgl.deb
RUN apt-get update && apt-get install -y --no-install-recommends \
	/tmp/virtualgl.deb \
	ffmpeg \
	fontconfig \
	fonts-dejavu-core \
	hsetroot \
	libdbus-1-3 \
	libegl-mesa0 \
	libegl1 \
	libgbm1 \
	libgl1 \
	libgl1-mesa-dri \
	libglx-mesa0 \
	libpulse0 \
	libx11-6 \
	libxcursor1 \
	libxext6 \
	libxi6 \
	libxinerama1 \
	libxkbcommon0 \
	libxrandr2 \
	pulseaudio \
	xvfb \
	&& rm -rf /var/lib/apt/lists/* /tmp/virtualgl.deb
COPY --from=game /usr/local/bin/godot /usr/local/bin/godot
COPY --from=game /game /game
COPY deploy/stream/override.cfg /game/override.cfg
# What deploy/stream/deploy prunes, so an old build's layers do not pile up.
LABEL grid-commanders.stream=true
ENTRYPOINT ["/game/deploy/stream/entrypoint.sh"]
