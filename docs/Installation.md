---
sidebar_position: 2
---

# Installation

## [Wally](https://wally.run) Package Manager

There are a few ways to install wally. You can find all the ways [here](https://wally.run/install). The recommended way is to use [Aftman](https://github.com/lpghatguy/aftman) and will be what's covered here.

1. Initialize Aftman if you haven't already. You can do this by opening a terminal in the project and running `aftman init`.

2. Add the wally tool to your `aftman.toml` file. In the same terminal as before run `aftman add UpliftGames/wally`. This should add the following to your `aftman.toml` file.

```toml title="aftman.toml"
[tools]
wally = "UpliftGames/wally@x.x.x"
```

3. Run `aftman install` to install wally and any other packages that you may have added.

4. If you don't have a `wally.toml` file, run `wally init`.

5. Add matter under `[dependencies]` inside `wally.toml`. You can find the latest version from [this page](https://wally.run/package/matter-ecs/matter) or by running `wally search matter-ecs` and finding the one labeled `matter-ecs/matter@x.x.x`.

```toml title="wally.toml"
[dependencies]
matter = "matter-ecs/matter@x.x.x" # Replace x.x.x with the latest version
```

6. Run `wally install`.
7. Sync in the `Packages` folder with [Rojo](https://rojo.space).

## Manual

1. Download `matter.rbxm` from the [latest release](https://github.com/matter-ecs/matter/releases/latest).
2. Sync in with [Rojo](https://rojo.space) or import into Roblox Studio manually.
