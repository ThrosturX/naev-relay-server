#!/usr/bin/env lua

--[[
    Naev Multiplayer Root Relay Server

    This server maintains a directory of peer-hosted game systems
    and allows clients to discover which peer is hosting which system.

    Protocol:
    - Client -> Server: "advertise\n<system_name>\n"
    - Client -> Server: "find\n<system_name>\n"
    - Server -> Client: "found\n<peer_address>\n" or "not_found\n"
    - Client -> Server: "heartbeat\n<system_name>\n" (every 30s)
]]

local enet = require "enet"
local socket = require "socket"

-- Configuration
-- Use env var PORT if available, otherwise default to 60939
local PORT = tonumber(os.getenv("PORT")) or 60939
local HEARTBEAT_TIMEOUT = 90  -- seconds before considering a peer dead
local CLEANUP_INTERVAL = 30   -- how often to clean up stale peers

-- Data structure: { system_name = { peer_object, address_string, last_seen } }
local hosted_systems = {}

-- Logging helper
local function log(message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    print(string.format("[%s] %s", timestamp, message))
end

-- Clean up stale peer entries
local function cleanup_stale_peers()
    local now = os.time()
    local removed = 0

    for system_name, info in pairs(hosted_systems) do
        if now - info.last_seen > HEARTBEAT_TIMEOUT then
            log(string.format("Removing stale entry for system '%s' (last seen %ds ago)",
                system_name, now - info.last_seen))
            hosted_systems[system_name] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then
        log(string.format("Cleaned up %d stale peer(s).", removed))
    end
end

-- Count active systems
local function count_systems()
    local count = 0
    for _ in pairs(hosted_systems) do
        count = count + 1
    end
    return count
end

-- Parse incoming message
local function parse_message(data)
    local lines = {}
    for line in data:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    return lines
end

-- Handle advertise message
local function handle_advertise(peer, system_name)
    local peer_addr = peer:get_address() -- Returns "IP:port" string

    if hosted_systems[system_name] then
        log(string.format("UPDATE: System '%s' now hosted by %s (was %s)",
            system_name, peer_addr, hosted_systems[system_name].address))
    else
        log(string.format("NEW: System '%s' now hosted by %s", system_name, peer_addr))
    end

    hosted_systems[system_name] = {
        peer = peer,
        address = peer_addr,
        last_seen = os.time()
    }

    peer:send("advertise_ack\n" .. system_name .. "\n")
end

-- Handle find message
local function handle_find(peer, system_name)
    log(string.format("QUERY: Peer %s looking for system '%s'",
        peer:get_address(), system_name))

    if hosted_systems[system_name] then
        local host_info = hosted_systems[system_name]
        local age = os.time() - host_info.last_seen

        if age < HEARTBEAT_TIMEOUT then
            log(string.format("FOUND: Directing to %s (last seen %ds ago)",
                host_info.address, age))
            peer:send("found\n" .. host_info.address .. "\n")
        else
            log(string.format("STALE: System found but last seen %ds ago", age))
            peer:send("not_found\n")
        end
    else
        log("NOT FOUND: No host for this system")
        peer:send("not_found\n")
    end
end

-- Handle heartbeat message
local function handle_heartbeat(peer, system_name)
    if hosted_systems[system_name] then
        local peer_addr = peer:get_address()
        if hosted_systems[system_name].address == peer_addr then
            hosted_systems[system_name].last_seen = os.time()
            -- Silently acknowledge (no need to spam logs)
            peer:send("heartbeat_ack\n")
        else
            log(string.format("WARNING: Heartbeat from wrong peer for system '%s'", system_name))
        end
    end
end

-- Handle deadvertise (peer stopping hosting)
local function handle_deadvertise(peer, system_name)
    if hosted_systems[system_name] then
        local peer_addr = peer:get_address()
        if hosted_systems[system_name].address == peer_addr then
            log(string.format("SHUTDOWN: System '%s' no longer hosted by %s",
                system_name, peer_addr))
            hosted_systems[system_name] = nil
            peer:send("deadvertise_ack\n")
        end
    end
end

-- Handle list message (for debugging/monitoring)
local function handle_list(peer)
    local response = string.format("active_systems\n%d\n", count_systems())
    for system_name, info in pairs(hosted_systems) do
        local age = os.time() - info.last_seen
        response = response .. string.format("%s,%s,%d\n",
            system_name, info.address, age)
    end
    peer:send(response)
end

-- Main message handler
local function handle_message(peer, data)
    local lines = parse_message(data)

    if #lines < 1 then
        log("WARNING: Received empty message")
        return
    end

    local command = lines[1]
    local arg = lines[2]

    if command == "advertise" and arg then
        handle_advertise(peer, arg)
    elseif command == "find" and arg then
        handle_find(peer, arg)
    elseif command == "heartbeat" and arg then
        handle_heartbeat(peer, arg)
    elseif command == "deadvertise" and arg then
        handle_deadvertise(peer, arg)
    elseif command == "list" then
        handle_list(peer)
    else
        log(string.format("WARNING: Unknown command '%s' from %s",
            command, peer:get_address()))
        peer:send("error\nUnknown command\n")
    end
end

-- Main server loop
local function main()
    log("=================================")
    log("Naev Multiplayer Root Relay Server")
    log("=================================")
    log(string.format("Starting relay server on port %d...", PORT))

    -- 0.0.0.0 means listen on all available network interfaces
    local host = enet.host_create("0.0.0.0:" .. PORT)

    if not host then
        log("ERROR: Failed to create ENet host!")
        os.exit(1)
    end

    log("Waiting for connections...")

    local last_cleanup = os.time()

    while true do
        -- Service network events (100ms timeout)
        local event = host:service(100)

        while event do
            if event.type == "connect" then
                log(string.format("CONNECT: Peer connected from %s",
                    event.peer:get_address()))

            elseif event.type == "receive" then
                handle_message(event.peer, event.data)

            elseif event.type == "disconnect" then
                log(string.format("DISCONNECT: Peer %s disconnected",
                    event.peer:get_address()))

                -- Clean up any systems this peer was hosting
                for system_name, info in pairs(hosted_systems) do
                    if info.peer == event.peer then
                        log(string.format("AUTO-CLEANUP: Removing system '%s' (host disconnected)",
                            system_name))
                        hosted_systems[system_name] = nil
                    end
                end
            end

            event = host:service(0)
        end

        -- Periodic cleanup of stale entries
        local now = os.time()
        if now - last_cleanup >= CLEANUP_INTERVAL then
            cleanup_stale_peers()
            last_cleanup = now
        end

        -- Small sleep is handled by host:service timeout
    end
end

-- Run the server
local status, err = pcall(main)
if not status then
    log(string.format("FATAL ERROR: %s", err))
    os.exit(1)
end
