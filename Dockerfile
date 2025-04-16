# Use latest stable channel SDK.
FROM dart:3.7.2 AS build

# Configure Git to avoid hardlink issues in Docker
RUN git config --global core.autocrlf false && \
    git config --global core.symlinks false && \
    git config --global core.preloadIndex false && \
    git config --global core.useBuiltin false && \
    git config --global pack.threads 1

# Resolve app dependencies.
WORKDIR /app/server
RUN mkdir -p ../api
COPY api/pubspec.* ../api/
COPY server/pubspec.* ./

# Use a modified pub get approach to avoid git cache issues
RUN dart pub get --no-precompile

# Copy app source code (except anything in .dockerignore) and AOT compile app.
COPY server .
COPY api ../api
RUN dart pub get --offline
RUN dart compile exe bin/swamp.dart -o bin/server

# Build minimal serving image from AOT-compiled `/server`
# and the pre-built AOT-runtime in the `/runtime/` directory of the base image.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/server /app/bin/

# Start server.
EXPOSE 8080
CMD ["/app/bin/server"]
