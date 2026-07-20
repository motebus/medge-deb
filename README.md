# MEdge Binary Packages

This public repository distributes install-only MEdge Debian packages for
Ubuntu 24.04 amd64.

It contains distribution documentation, the public APT key, release
manifests, and GitHub Pages automation. Component source code and Debian
source packages are intentionally absent. Canonical source and builds remain
on GitLab.

## Install

Download and inspect the public archive-key fingerprint:

```text
94BE 0969 7B28 5F1C E6A8  F15B F643 AB45 5530 81EE
```

Install the key and repository definition:

```bash
sudo install -d -m 0755 /etc/apt/keyrings

curl -fsSLo /tmp/medge-archive-keyring.gpg \
  https://motebus.github.io/medge-deb/medge-archive-keyring.gpg
sudo install -m 0644 /tmp/medge-archive-keyring.gpg \
  /etc/apt/keyrings/medge-archive-keyring.gpg

curl -fsSLo /tmp/medge.sources \
  https://motebus.github.io/medge-deb/medge.sources
sudo install -m 0644 /tmp/medge.sources \
  /etc/apt/sources.list.d/medge.sources

sudo apt-get update
sudo apt-get install medge
```

The repository uses:

```text
suite:        stable
component:    main
architecture: amd64
```

It does not require `apt-key`, `trusted=yes`, or a direct DEB URL.

## Releases

Each approved GitHub Release contains:

- eight component binary DEBs;
- one dependency-only `medge` meta-package DEB;
- `release-manifest.json`;
- `SHA256SUMS`;
- optional binary `.changes` and `.buildinfo` provenance.

The `medge` package installs the exact coordinated versions of `sphered`,
`mbridge`, `ss-webos`, `moted`, `agos`, `qbix-wasm`, `mote`, and `desk`.

Every stable publication requires explicit owner approval. Existing release
tags and assets are immutable.
