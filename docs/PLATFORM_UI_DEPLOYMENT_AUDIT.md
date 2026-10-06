# Research OS Platform UI Deployment Audit

## Scope
This audit binds the canonical product UI, web artifact pipeline, and the existing Render API without retiring compatibility surfaces prematurely.

Audit baseline: `17027bdee5c88a4dbdd3fb5cc345e993aaaa071c`.

## Findings

### Canonical product UI
`apps/research_os_flutter` is the canonical Research OS product UI across Windows, Web and iOS.

Evidence:
- `apps/research_os_flutter/lib/src/research_os_app.dart` composes the canonical application.
- `apps/research_os_flutter/lib/src/app_shell.dart` explicitly states that the product UI is canonical and shared across Windows, Web and iOS.
- `docs/RESEARCH_OS_FLUTTER_FEATURE_MAPPING.md` names `apps/research_os_flutter` as the canonical product UI surface and keeps the other Flutter roots as compatibility/runtime boundaries until proven migrated.

### Legacy web surface
`apps/research_os_web` is a real legacy/static web surface.

Its current HTML identifies itself as `Research OS 3.2 — Wide Research` and exposes the older Research / Evidence / Workspace / Providers navigation.

It must not be treated as the canonical product UI.

It remains in the artifact/installer pipeline as a compatibility surface until its references and consumers are migrated and retirement is proven.

### Artifact pipeline mismatch found and corrected
The website artifact workflow previously built the canonical Flutter web app with:

`RESEARCH_OS_API_BASE_URL=http://127.0.0.1:8787`

That is a local development endpoint and is not suitable as the production web binding.

The workflow now builds the canonical Flutter web artifact against:

`https://research-os-api-phakphoum-v0wf.onrender.com`

The manifest now explicitly distinguishes:
- canonical UI: `apps/research_os_flutter` -> `flutter-web`
- compatibility UI: `apps/research_os_web` -> `website-static`

### Render API contract
The canonical Render service configuration is represented by `render.yaml`:
- service: `research-os-api-phakphoum`
- health path: `/health`
- start command: `cd tools/research_os_api && python render_server.py`
- public base URL: `https://research-os-api-phakphoum-v0wf.onrender.com`
- Google identity callback: `https://research-os-api-phakphoum-v0wf.onrender.com/v1/auth/google/callback`
- allowed browser origin currently configured as `https://phakphoum38-stack.github.io`

The production Render service is now independently verified through the connected Render workspace: service `srv-db2jv449v7es738cejm0`, branch `main`, repository `phakphum12345/ENTERPRISE_API_ARCHITECTURE_LOGIC_TH`, and live deploy `dep-db2k5up42hec738q5b2g` at canonical SHA `ec19ce664f1430c90313bf69b38ca37be4c0a56c`. The live Render URL is `https://research-os-api-phakphoum-v0wf.onrender.com`.

### Authentication boundary
The canonical Flutter app calls the server auth-status endpoint during startup.

The server-side auth route derives identity from the signed Research OS session rather than trusting client-provided identity.

Google production OIDC hardening is already on canonical main; production runtime proof remains a separate release-gate requirement.

## Release state
`PLATFORM_RELEASE_HOLD`

The following deployment evidence is still required before release authority can be granted:
1. Identify the actual production web deployment provider and URL.
2. Bind that deployment to an exact canonical commit SHA.
3. Prove the deployed web artifact is the `flutter-web` artifact from that SHA.
4. Prove the deployed web app uses the canonical Render API.
5. Execute real Google login through the deployed UI.
6. Verify `/v1/auth/status` returns server-derived identity.
7. Execute negative tests for invalid/replayed OAuth state and forged/expired/revoked sessions.
8. Record the immutable UI-SHA + API-SHA + artifact + deployment + auth evidence packet.

No legacy UI root is deleted by this change. No Git history is rewritten.
