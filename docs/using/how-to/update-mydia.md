# Updating Mydia

This guide covers updating an existing Mydia installation, tracking pre-release builds, and pinning to a specific version.

!!! warning "Back up before you upgrade"
    Mydia applies pending migrations on startup. On SQLite it snapshots the
    database first, beside the original, which covers a migration going wrong but
    not the disk it lives on. On PostgreSQL it takes no backup at all. Take your
    own before pulling a new image. See
    [Backing Up and Restoring](backup-restore.md).

## Via Docker Compose

```bash
docker compose pull
docker compose up -d
```

## Via Docker CLI

```bash
docker stop mydia
docker rm mydia
docker pull ghcr.io/kawaii-not-kawaii/mydia:master
# Run your docker run command again
```

Migrations run automatically on startup, after Mydia snapshots the SQLite
database (see [Backing Up and Restoring](backup-restore.md)). Your data in
`/config` is preserved.

## Available Tags

This fork publishes two rolling tags, both rebuilt from every commit on the
default branch:

```yaml
services:
  mydia:
    image: ghcr.io/kawaii-not-kawaii/mydia:master
```

PostgreSQL users need the `-pg` variant:

```yaml
services:
  mydia:
    image: ghcr.io/kawaii-not-kawaii/mydia:master-pg
```

!!! warning "These builds are amd64 only"
    `master` and `master-pg` are `linux/amd64` and nothing else. They will not
    run on a Raspberry Pi, an arm64 server, or Apple Silicon. Multi-arch images
    are produced by the release workflow, so on arm64 hardware you need to build
    locally with `docker build -t mydia .`.

Because they track the default branch, these tags:

- May contain experimental features
- May have breaking changes
- Are not covered by release notes, so read the commit log if something changes under you

## Version Pinning

There are no `latest`, `beta` or version tags yet: those are produced by the
release workflow, which has not been run on this fork. Until a release is cut,
pin by digest if you need a fixed version:

```yaml
services:
  mydia:
    image: ghcr.io/kawaii-not-kawaii/mydia@sha256:<digest>
```

Read the digest of what you are running with
`docker inspect --format '{{index .RepoDigests 0}}' mydia`.
