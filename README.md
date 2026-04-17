# Tokenmon

[English](README.md) | [한국어](README.ko.md)

Turn everyday AI coding into a quiet creature-collection loop.

Tokenmon is a macOS menu bar companion for people who spend their day in Claude
Code and Codex. Keep coding like normal, let exploration build in the
background, and watch new creatures appear, resolve, and fill your Dex without
asking for an account or your prompt history.

![Tokenmon animated menu hero](assets/screenshots/variants/english/dark/menu-hero.gif)

## Download

- [Download the latest macOS release (DMG)](https://github.com/aroido/tokenmon/releases/latest)
- Install with Homebrew:

```bash
brew install --cask aroido/tokenmon/tokenmon
```

- Requires macOS Sequoia or later

## Why People Keep It Open

- Your normal AI coding sessions become light exploration and surprise
  encounters.
- The app stays out of the way in the menu bar until you want a quick glance.
- Everything is local-first, offline-first, and designed to work without an
  account.
- Gameplay works without storing your prompt or response text.
- Release builds can update in-app, so trying Tokenmon stays low-friction.

## Screenshots

<p align="center">
  <img src="assets/screenshots/variants/english/dark/menu-overview.png" alt="Tokenmon menu overview" width="31%" />
  <img src="assets/screenshots/variants/english/dark/seen-dex.png" alt="Tokenmon seen dex" width="31%" />
  <img src="assets/screenshots/variants/english/dark/settings.png" alt="Tokenmon settings" width="31%" />
</p>

## Public Source Repo

- This repository is the public, source-available mirror of shipped Tokenmon
  snapshots.
- GitHub Releases, Sparkle updates, and Homebrew installs are published from
  this repository.
- Day-to-day development, maintainer workflows, and internal review artifacts
  live outside this public mirror.
- Treat this repo as a buildable release snapshot, not as the primary
  day-to-day collaboration lane.

## Build From Source

```bash
swift build
./scripts/ai-verify --mode pr
./scripts/build-release
```

## Docs

- [Public source overview](docs/architecture/public-source-overview.md)
- [Public docs index](docs/INDEX.md)

## License

Tokenmon code is source-available under
[FSL-1.1-ALv2](LICENSE.md). Current versions are not OSI open source: the source
is available, but competing commercial use is restricted. Two years after a
version is published, that version converts to Apache 2.0.

Creative assets are licensed separately under
[LICENSE-assets.md](LICENSE-assets.md), and names/logos are governed by
[TRADEMARKS.md](TRADEMARKS.md).
