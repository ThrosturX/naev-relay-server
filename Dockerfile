FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    lua5.4 \
    luarocks \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN luarocks install luasocket
RUN luarocks install enet

WORKDIR /app
COPY relay_server.lua /app/relay_server.lua
RUN chmod +x /app/relay_server.lua

ENV PORT=60939
EXPOSE ${PORT}

CMD ["lua", "/app/relay_server.lua"]
