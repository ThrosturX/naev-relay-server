# Dockerfile for Naev Multiplayer Relay Server

FROM debian:bookworm-slim

# Install Lua, LuaRocks, build dependencies, and ENet library
RUN apt-get update && apt-get install -y \
    lua5.4 \
    luarocks \
    git \
    build-essential \
    libenet-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Lua dependencies
RUN luarocks install luasocket
RUN luarocks install enet

# Create app directory
WORKDIR /app

# Copy server script
COPY relay_server.lua /app/relay_server.lua

# Make it executable
RUN chmod +x /app/relay_server.lua

# Railway provides PORT env variable, but default to 60939 for local testing
ENV PORT=60939

# Expose the port (Railway will override this with its own PORT)
EXPOSE ${PORT}

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD lua -e "require('socket'); s=socket.tcp(); s:settimeout(1); assert(s:connect('localhost', os.getenv('PORT') or 60939))"

# Run the server
CMD ["lua", "/app/relay_server.lua"]
