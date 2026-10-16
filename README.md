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
newest stable slot. Images update automatically after a stable server or CLI
release; the hourly publisher rebuilds slots whose pinned versions changed.
Only stable images are published. Slot tags follow the newest package for that slot.

## Build from native packages

```sh
docker build -t ghcr.io/gelstable/gel:local \
  --build-arg version=7 \
  --build-arg exact_version=1:7.1-1 \
  --build-arg cli_version=1:7.2-1 .
```

`version` is the required server slot; `exact_version` is the required full
Debian version including epoch and revision, without wildcards. `subdist` selects
`stable` (default) or `testing`. The build fails if the exact version is absent.
`cli_version` is the required full native CLI version. The image pins `gel-cli`
and retains the same authenticated APT source for runtime `GEL_DOCKER_EXTENSIONS` installations.

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
package version. The **Publish GHCR image** workflow runs hourly and can be
started manually. To force a rebuild, open the workflow's **Run workflow** form
and enter a server `slot` (for example `7`); leave it empty to reconcile all
slots normally. It compares the stable amd64 and arm64 indexes with image
labels, tests both architectures, and publishes the tested multiarch images.
A new CLI package rebuilds every slot. `latest` follows the newest stable slot.
Branch runs only print planned tags and version labels without building or
publishing. An empty registry succeeds without building. Scheduled failures
open or update one issue, which closes after the next successful run on the default branch.

Run the fixture planner checks without Docker using
`python3 -m unittest discover -s tests -p 'test_*.py'` (requires `python3-debian`).
