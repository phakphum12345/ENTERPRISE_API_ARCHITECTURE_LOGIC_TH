# Research OS Dynamic Service Port Protocol

- Protocol ID: ROS-PORT-DISCOVERY-001
- Version: 1
- Status: PROPOSED — implementation must pass CI and runtime verification before ACTIVE
- Scope: local Research OS services and desktop clients

## Objective

Remove fixed local TCP port assumptions. Each local service asks the operating system to bind an available port (TCP port 0), then publishes the actual bound endpoint to a local service registry. Clients resolve services by stable service identifier, never by a remembered port number.

## Required lifecycle

1. READ the existing service entrypoint, installer, Windows ServiceHost, Flutter client, environment variables, tests and port-topology contracts.
2. ANALYZE every consumer and provider of each endpoint; map service identity and ownership before changing launch behavior.
3. A server MUST bind its listening socket before publishing an endpoint. The OS-assigned port MUST be read from the bound server socket; a separate free-port probe followed by a later bind is forbidden because it is subject to TOCTOU races.
4. The registry MUST use one atomic file per service, with schema version, service ID, protocol, loopback host, assigned port, base URL and owning PID.
5. Registry writes MUST use a same-directory temporary file, flush/fsync and atomic replace. Registry removal MUST be guarded by owning PID so an old process cannot erase a replacement process's record.
6. A consumer MUST resolve by service ID, validate the record, perform a bounded health check and fail closed when missing/stale. It MUST NOT silently substitute a different service or mock provider.
7. Restart MUST publish the new endpoint before reporting READY. Shutdown MUST remove only the record owned by that process.
8. Cloud endpoints remain explicit HTTPS URLs supplied by deployment configuration. Cloud port assignment is owned by the hosting platform.
9. Ollama's existing endpoint/port is externally managed and MUST NOT be changed by this protocol.
10. Port numbers MUST NOT be used as identity, authorization, tenancy or privilege. Authentication and authorization remain independent of service discovery.

## Security

- Local service registry records are metadata, not credentials.
- Local APIs MUST bind to loopback by default unless a separately reviewed network-exposure contract authorizes otherwise.
- Do not publish wildcard (0.0.0.0) or LAN endpoints to the local desktop registry.
- Do not expose secrets, tokens, passwords or session material in registry files or logs.
- Reject malformed service IDs, unknown schema versions, invalid hosts, invalid ports and malformed base URLs.
- Never terminate a process merely because it owns a port; process identity must be verified.

## Compatibility and migration

- Existing data directories, session stores, databases, logs and credentials MUST remain unchanged.
- Existing fixed-port values may be accepted only as an explicit compatibility override during migration; default local startup must request OS allocation.
- UI labels must use service names (for example, Research OS API and Owner Friend), not PORT 1 / PORT 2.
- Existing cloud URL configuration remains supported.
- Ollama is not part of local port migration.

## Required verification

- Unit tests for port-0 binding, registry schema, atomic publication, malformed/stale records and PID-guarded removal.
- API and Friend service startup tests proving the published port equals the actual bound socket.
- Flutter tests proving service-ID discovery and dynamic endpoint refresh after restart.
- Windows ServiceHost and installer tests proving the endpoint is available to the desktop user and no fixed local port remains in the launch path.
- End-to-end: start services, read registry, call health endpoints, restart and verify endpoint refresh, stop and verify cleanup.
- Negative test: missing registry or failed health check MUST be reported as unavailable; never fake READY.
- Regression: Ollama endpoint and existing Local/Cloud data paths remain unchanged.

## Release gate

Do not merge or claim operational readiness until the required checks pass on the exact PR head SHA and a real runtime smoke test confirms service discovery. Static tests alone do not prove runtime availability.
