#!/usr/bin/env lua

--[[
    Naev Multiplayer Root Relay Server
    Protocol:
    - Client -> Server: "advertise\n<system_name>\n"
    - Client -> Server: "find\n<system_name>\n"
    - Server -> Client: "found\n<peer_address>\n" or "not_found\n"
    - Client -> Server: "heartbeat\n<system_name>\n" (every 30s)
]]

local enet = require "enet"
local socket = require "socket"

local PORT = tonumber(os.getenv("PORT")) or 60939
local HEARTBEAT_TIMEOUT = 90
local CLEANUP_INTERVAL = 30

local hosted_systems = {}

local function log(message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    print(string.format("[%s] %s", timestamp, message))
end

local function cleanup_stale_peers()
    local now = os.time()
    local removed = 0
    
    for system_name, info in pairs(hosted_systems) do
        if now - info.last_seen > HEARTBEAT_TIMEOUT then
            log(string.format("Removing stale entry for system '%s'", system_name))
            hosted_systems[system_name] = nil
            removed = removed + 1
        end
    end
    
    if removed > 0 then
        local count = 0
        for _ in pairs(hosted_systems) do count = count + 1 end
        log(string.format("Cleaned up %d stale peer(s). Active: %d", removed, count))
    end
end

local function parse_message(data)
    local lines = {}
    for line in data:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    return lines
end

local function handle_advertise(peer, system_name)
    local peer_addr = peer:get_address()
    log(string.format("ADVERTISE: System '%s' by %s", system_name, peer_addr))
    
    hosted_systems[system_name] = {
        peer = peer,
        address = peer_addr,
        last_seen = os.time()
    }
    
    peer:send("advertise_ack\n" .. system_name .. "\n")
end

local function handle_find(peer, system_name)
    log(string.format("FIND: '%s' by %s", system_name, peer:get_address()))
    
    if hosted_systems[system_name] then
        local host_info = hosted_systems[system_name]
        local age = os.time() - host_info.last_seen
        
        if age < HEARTBEAT_TIMEOUT then
            log(string.format("FOUND: %s (age: %ds)", host_info.address, age))
            peer:send("found\n" .. host_info.address .. "\n")
        else
            peer:send("not_found\n")
        end
    else
        peer:send("not_found\n")
    end
end

local function handle_heartbeat(peer, system_name)
    if hosted_systems[system_name] then
        local peer_addr = peer:get_address()
        if hosted_systems[system_name].address == peer_addr then
            hosted_systems[system_name].last_seen = os.time()
            peer:send("heartbeat_ack\n")
        end
    end
end

local function handle_deadvertise(peer, system_name)
    if hosted_systems[system_name] then
        local peer_addr = peer:get_address()
        if hosted_systems[system_name].address == peer_addr then
            log(string.format("DEADVERTISE: System '%s'", system_name))
            hosted_systems[system_name] = nil
            peer:send("deadvertise_ack\n")
        end
    end
end

local function handle_list(peer)
    local count = 0
    for _ in pairs(hosted_systems) do count = count + 1 end
    
    local response = string.format("active_systems\n%d\n", count)
    for system_name, info in pairs(hosted_systems) do
        local age = os.time() - info.last_seen
        response = response .. string.format("%s,%s,%d\n", system_name, info.address, age)
    end
    peer:send(response)
end

local function handle_message(peer, data)
    local lines = parse_message(data)
    if #lines < 1 then return end
    
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
        peer:send("error\nUnknown command\n")
    end
end

local function main()
    log("=================================")
    log("Naev Multiplayer Root Relay Server")
    log("=================================")
    log(string.format("Starting on port %d...", PORT))
    
    local host = enet.host_create(string.format("*:%d", PORT))
    
    if not host then
        log("ERROR: Failed to create ENet host!")
        os.exit(1)
    end
    
    log(string.format("Listening on %s", host:get_socket_address()))
    
    local last_cleanup = os.time()
    
    while true do
        local event = host:service(1)
        
        while event do
            if event.type == "connect" then
                log(string.format("CONNECT: %s", event.peer:get_address()))
            elseif event.type == "receive" then
                handle_message(event.peer, event.data)
            elseif event.type == "disconnect" then
                log(string.format("DISCONNECT: %s", event.peer:get_address()))
                for system_name, info in pairs(hosted_systems) do
                    if info.peer == event.peer then
                        hosted_systems[system_name] = nil
                    end
                end
            end
            event = host:service(1)
        end
        
        local now = os.time()
        if now - last_cleanup >= CLEANUP_INTERVAL then
            cleanup_stale_peers()
            last_cleanup = now
        end
        
        socket.sleep(0.01)
    end
end

local status, err = pcall(main)
if not status then
    log(string.format("FATAL: %s", err))
    os.exit(1)
end
