# polyresolver

Universal DNS-compatible name resolver for alternative, blockchain, and mesh networks.

> **Status:** Vision + SRS + SAD specification project (Phase 0 development)

## Overview

`polyresolver` provides a unified DNS-compatible interface to heterogeneous naming spaces:
- Classical DNS
- Blockchain registries (Handshake, ENS, Namecoin/ncdns, EmerDNS)
- Anonymization networks (Tor, I2P/i2pd)
- Mesh and overlay networks (Yggdrasil, cjdns, Reticulum, OLSR, Meshtastic, Babel, Serval)
- Decentralized storage (IPFS/IPNS, ZeroNet, Hyphanet, GNUnet/GNS)
- Experimental darknet networks (dn42, anoNet)
- Reputation filtering systems (DNSBL/DRBL)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Edge Layer                            │
│                  dnsdist (ACL, DoT/DoH/DoQ)                  │
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                    polyresolver-core                         │
│  Routing Engine │ STM Cache │ ResolutionGraph │ Supervisor Tree │
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                       Adapters                              │
│  Unbound │ ncdns │ EmerDNS │ hsd │ ENS │ Tor │ I2P │ ...     │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
polyresolver/
├── polyresolver-types/        # Common types: ResolveRequest, ResolveResult, ZonePattern
├── polyresolver-core/         # Routing Engine, Supervisor Tree, STM Cache
├── polyresolver-dns/          # DNS wire protocol via dnsext
├── polyresolver-api/          # Servant backend API
├── polyresolver-metrics/      # Prometheus integration
├── polyresolver-config/       # YAML loader, schema, hot-reload
├── polyresolver-plugin-sdk/   # Plugin SDK: ABI, IPC client/server
├── polyresolver-adapter-*/    # Adapter implementations
├── polyresolver-ctl/          # CLI utility
└── polyresolver-server/       # Executable combining all components
```

## Requirements

- GHC 9.4+ (tested with 9.6.x)
- Cabal 3.10+
- `dnsdist` for edge layer (optional, recommended)

## Building

```bash
# Clone and enter the project
git clone https://github.com/nousresearch/polyresolver.git
cd polyresolver

# Build
cabal update
cabal build all

# Run tests
cabal test

# Build executable
cabal install polyresolver-server
```

## Configuration

See `examples/polyresolver.yaml` for a complete configuration example.

Key configuration options:
- `listeners` - DNS and API endpoints
- `adapters` - Enabled adapters and their settings
- `cache` - STM cache tuning parameters
- `views` - Access control policy

## Development Phases

| Phase | Components |
|-------|------------|
| 0 | polyresolver-types, core, DNS, Unbound adapter |
| 1 | ncdns, EmerDNS, hsd, ENS adapters |
| 2 | Tor, I2P, IPFS/IPNS, DNSBL, Plugin SDK |
| 3+ | GNUnet/GNS, Reticulum, OpenTelemetry, persistent cache |

## License

MPL-2.0

## References

- [Technical Specification](docs/TECHNICAL_SPECIFICATION.md)
- [Developer Guide](docs/DEVELOPER_GUIDE.md)
- [Security Model](docs/SECURITY_MODEL.md)