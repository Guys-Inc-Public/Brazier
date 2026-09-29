# Brazier app

SwiftUI, iOS 17+, no third-party packages. The Xcode project is generated from `project.yml` with xcodegen and is not committed.

## Build on the Mac mini

From mitochondria, `scripts/remote.sh` stages this directory on the Mac and runs a Makefile target there as the `claude` build user:

```
scripts/remote.sh build-sim            # generate the project and build for the iPhone 17 Pro simulator
scripts/remote.sh run-sim              # build, install, launch, screenshot to /Users/Shared/brazier/app-screenshot.png
scripts/remote.sh run-sim SEED_URL=https://grafana.example.org SEED_TOKEN=glsa_… SEED_NAME=Lab   # DEBUG only: mount a token-mode server at launch
scripts/remote.sh archive              # Release archive with cloud signing (needs the App Store Connect app record)
scripts/remote.sh upload               # export the archive to TestFlight
```

On the Mac itself: `make build-sim`, `make run-sim`, `make archive`, `make upload`.

Simulators are per macOS user; the Makefile resolves `SIM_NAME` (default `iPhone 17 Pro`) to the build user's own device. Simulator builds are ad-hoc signed so the keychain works; an unsigned build has no entitlements and every keychain write fails.

## Layout

- `Brazier/App` — entry point, app delegate (APNs, notification actions), the root model.
- `Brazier/Brand` — the eleven colours, the two variable fonts, the interface parts (lamp, chip, latch, fault card, guarded throw).
- `Brazier/Models` — servers, Grafana API models, the push payload.
- `Brazier/Services` — keychain, OIDC with PKCE, credentials, the Grafana client, the relay client, push, silences.
- `Brazier/Views` — alerts, servers, dashboards (milestone 3 stub), settings.
- `Brazier/Resources` — asset catalog (icon, mark), fonts with their OFL licences.

Design: Guys Inc Branding Standards, instrument profile. Identifiers: `docs/reference/identifiers.md`.
