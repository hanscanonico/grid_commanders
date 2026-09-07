# The web build, exported and served. Two stages so the image that runs on the
# mini PC holds nginx and the exported page, never the engine.
#
# Stage 1 is the same headless import-then-export `make export-web` runs, on the
# Linux build of the engine the repo vendors for macOS: the godot-ci tag is pinned
# to that version because a template mismatch fails the export outright.
FROM barichello/godot-ci:4.7.1 AS export
WORKDIR /src
COPY . .
RUN godot --headless --path . --import \
	&& mkdir -p /build/web \
	&& godot --headless --path . --export-release "Web" /build/web/index.html

FROM nginx:1.27-alpine
COPY --from=export /build/web /usr/share/nginx/html
COPY deploy/web/nginx.conf /etc/nginx/conf.d/default.conf
