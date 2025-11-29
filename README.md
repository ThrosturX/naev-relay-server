# Naev Multiplayer Root Relay Server

Root relay server for the Naev multiplayer P2P mode.

## Deployment

This server is deployed on Railway.app.

## Protocol

- `advertise <system_name>` - Register as hosting a system
- `find <system_name>` - Find who's hosting a system
- `heartbeat <system_name>` - Keep registration alive
- `deadvertise <system_name>` - Stop hosting a system
- `list` - List all active systems

## Testing

See the test_relay.lua script in the main repository.
