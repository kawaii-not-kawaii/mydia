# API Reference

!!! info "Internal APIs"
    Mydia exposes an HTTP API primarily for internal use by its own web UI. It is not yet stable or documented for third-party consumption.

## Current State

Mydia includes several internal API surfaces used by its own components:

| Area | Description |
|------|-------------|
| **Downloads** | Download client management and status |
| **Indexers** | Search queries to configured indexers |
| **Media** | Library browsing, metadata, and management |
| **Subtitles** | Subtitle search and download |
| **Admin/Config** | Server configuration and settings |

Mydia does not play media, so there are no playback, streaming or transcoding
session endpoints. Point Plex, Jellyfin, Infuse or VLC at the library instead.

Mydia does not expose webhook endpoints. Download clients are not asked to call
back into Mydia; a background job polls each configured client for status instead.
See [The Media Pipeline](../explanation/media-pipeline.md) for how that loop works.

## Stability

These APIs are **internal** and may change between versions without notice. If you're interested in a stable public API for third-party integrations, please open a [feature request](https://github.com/getmydia/mydia/issues/new).

## Integration Options

Currently, you can integrate with Mydia through:

1. **Download Clients** - Configure in Admin UI
2. **Indexers** - Configure in Admin UI
3. **OIDC/SSO** - Authenticate via external identity providers

## Contributing

If you're interested in API development, check the [Development](../../contributing/setup.md) documentation and consider contributing to the project.
