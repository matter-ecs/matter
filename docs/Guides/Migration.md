# Migration
## Migrating from evaera/matter to matter-ecs/matter
Migrating from `evaera/matter` to `matter-ecs/matter` is easy! The only thing you need to do is change the package name in your `wally.toml` file.

  ```toml title="wally.toml"
  [dependencies]
  matter = "matter-ecs/matter@x.x.x" # Replace x.x.x with the version you want to use
  ```
