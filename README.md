# The Gelstable Docker image for Gel

This repository contains the Gelstable maintained Docker image packaging
Gel and the Gel CLI.

#### ✨[Documentation](https://docs.geldata.com/resources/guides/deployment/docker)✨

## When to use this image

This image is intended for use in production, or as part of a
development setup that involves multiple containers orchestrated by
Docker Compose or a similar tool. Otherwise, we recommend using the [`Gel CLI`](https://docs.geldata.com/learn/cli) to install Gel and
manage local instances.

## What is Gel?

[Gel](https://www.geldata.com) is an open-source object-relational database
built on top of PostgreSQL, featuring:

- strict, object-oriented typed schema;
- powerful and expressive query language;
- rich standard library;
- built-in support for schema migrations;
- native GraphQL support.

Try the [quickstart](https://docs.geldata.com/learn/quickstart/overview) or jump into the [docs](https://docs.geldata.com/) to get started with Gel.

## Image and tags

Pull `ghcr.io/gelstable/gel:7` for a server slot or
`ghcr.io/gelstable/gel:7.1` for an exact product version. `latest` follows the
newest stable slot. Testing builds are selected explicitly during publication;
the exact product tag renders prerelease `~` as `-` (for example `7.2-rc.1`).
Slot tags follow the most recently published build for that slot.

## Build from native packages

```sh
docker build -t ghcr.io/gelstable/gel:local \
  --build-arg version=7 \
  --build-arg exact_version=1:7.1-1 .
```

`version` is the required server slot; `exact_version` is the required full
Debian version including epoch and revision, without wildcards. `subdist` selects
`stable` (default) or `testing`. The build fails if the exact version is absent.
The image installs `gel-cli` and retains the same authenticated APT source for
runtime `GEL_DOCKER_EXTENSIONS` installations.

`registry_url` defaults to `https://registry.gelstable.com`. `key_fingerprint`
pins the primary OpenPGP fingerprint of `/keys/gelstable.asc`; the downloaded
armored key must match before APT reads the repository. The current default is
the production signing key fingerprint
`EBFC46CC958983DD73D6E7D7F7C050A836EDB7EC`. For a local signed repository,
explicitly set both arguments to its URL and public key fingerprint.

## Tests and publication

With Docker, Docker Compose, and the Gel CLI installed on Linux, install
`bats`, `jq`, `parallel`, `python3-debian`, `curl`, and `uuid-runtime`, then run
`bats tests/*.bats`. Tests select the newest server slot and Debian version from
the channel's standard APT `Packages` index with Debian's version ordering.
Set `GEL_TEST_CHANNEL=testing` to select testing, or set `GEL_TEST_SLOT` and
`GEL_TEST_EXACT_VERSION` to select a specific native release. Local repository
checks may set `GEL_REGISTRY_URL` and `GEL_KEY_FINGERPRINT`.

CI tests both amd64 and arm64 with the packaged CLI, including runtime PostGIS
installation, schema migration, geometry queries, and an unchanged server
package version. The manual **Publish GHCR image** workflow runs only on the
default branch. It accepts a channel, slot, and full native version, tests both
architectures, then uses `GITHUB_TOKEN` to publish the tested images and a
multiarch manifest. It publishes `latest` only for the newest stable slot.
