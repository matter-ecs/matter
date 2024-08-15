# Matter Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][kac], and this project adheres to
[Semantic Versioning][semver].

[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html

## [Unreleased]

## [0.8.4] - 2024-08-15

### Added

- Better assertions / error messages added to `World` methods that accept
  variadic component arguments. At least 1 component must be provided. These
  assertions have been added to `get` `insert` `replace` `remove`
- Ability to sort the world inspect table by clicking the table headers (entity
  count and component name)
- Ability to disable systems in the debugger list by right clicking them.

### Changed

- The alt-hover tooltip's text is smaller and the background is slightly darker
  for improved legibility.
- Component data now has syntax highlighting applied. This is present in the
  **alt-hover tooltip** and the **entity inspector panel** in the debugger.

### Fixed

- The alt-hover tooltip now displays component data properly, with each
  component being displayed on a new line.
- Removed extra new-lines in component data strings within the debugger entity
  inspect tables.
- Fixed alt-hover erroring when hovered entity is despawned.
- Fixed flashing buttons ("View queries" and "View logs") in system inspect panel

## [0.8.3] - 2024-07-02

### Fixed

- Converted the remaining lua files in the example project to luau files.
- Iterating empty views properly iterates over nothing rather than the data structure members.

## [0.8.2] - 2024-06-25

### Changed

- Optimized `Views` performance.
  - No longer allocates a table for each entity in the view, making it much
    cheaper for queries that match against many entities.
- Converted the lua files to luau files.

### Fixed

- Calling `:view()` on an empty query will no longer error.
- Fixed `:snapshot()` on an empty query returning nil instead of an empty array.
- Fixed an error that would happen when calling an empty Query.
- Reverted the changes to the format of the debugger table.

## [0.8.1] - 2024-04-23

### Fixed

- `QueryResult:without` now correctly matches against entity archetype after
  cache has been invalidated from transitioning archetype.

## [0.8.0] - 2024-04-22

### Changed

- Added `Views` for random-accessing entities within queries.
  - Views are optimized for terse indexing, making them useful for traversing
    graphs of entities.
- Added `Debugger.loopParameterNames` which allows for labelling things passed
  to Loop.
- Disabled `AutoLocalize` on many Plasma Widgets.
  - This removes unnecessary computations for
    `LocalizationService::attemptLocalization`.
- Improved `QueryResult:without` to narrow archetype invariants.
  - The filter now works on the archetype-level rather than filtering entities
    ad-hoc which will immensely improve query performance.

### Fixed

- Fixed the Scheduler not respecting priorities of systems.
- Fixed padding of items in the Debugger's state view.

## [0.7.1] - 2024-01-31

### Changed

- Improved overall usability of the world inspect widget in the debugger.
  - The widget now displays a more table-like view of the world's entities and
    their components.
- Improved query unpacking performance when querying 5 components or fewer.
  - This covers the majority of use cases.
  - Querying more than 5 components remains unchanged.
- The debugger UI is more compact and includes minor layout improvements.
- The debugger panel now better displays system order and performance.

### Fixed

- Slider now properly supports passing only a number rather than a table.
- TestEZ is now a dev dependency rather than a regular dependency.
- Fixed regressions with system scheduling.
  - Scheduling systems with dependencies on other systems no longer incorrectly
    detects cycles.
  - Scheduling no longer occasionally produces non-deterministic ordering.

## [0.7.0] - 2023-12-19

### Added

- Created a debugger configuration `Debugger.componentRefreshFrequency` to
  change the unique component list's refresh frequency.

### Changed

- Change `Matter.log` to return _nothing_ as expected.
- Exported Matter object is now read only, which prevents invalid mutations to
  it.
- Improve documentation for `Matter.useEvent`.
- Systems with both after and priority defined will error.
- Error message for cycles should be more descriptive.
- Systems with dependencies should be scheduled after the system with the
  highest priority in it's "after" list.
- Improve error message for when a component instance is passed where a
  component is expected, e.g `world:remove(id, componentInstance())`.
- Improve implementation of the debugger's mouse hover feature, which now
  supports debugging the player's character model.

### Fixed

- Fix the debugger not showing a system's widgets properly when switching from
  one to another.
- Fix slider debugger widget returning 0 when not being rendered.

## [0.6.2] - 2022-07-22

### Fixed

- Debugger no longer interferes with `queryChanged` in order to display it in
  the debugger view. Previously, this caused the storage to get reset. This
  feature may return in the future.

## [0.6.1] - 2022-07-10

### Added

- Added `Matter.log`, and a logs viewer per-system to the Matter debugger.
- Added error logging and inspection to the Matter debugger.
- Added Query inspection to the Matter debugger.

### Fixed

- Fixed bug with server-side debugger when game was in deferred events mode.

## [0.6.0] - 2022-07-08

### Changed

- The first time you call `queryChanged`, all existing entities in the world
  that match the component are now returned as "new" change records. Previously,
  nothing was returned.
- Improved Debugger with highlight selections and tooltips.
- `Matter.useEvent` now supports events that have a `Connect`, `connect`, or an
  `on` method. Additionally, it also supports custom connection objects
  (returned by custom events), which have a `Destroy` or a `Disconnect` method,
  or are just a cleanup function.

### Fixed

- Debugger: Fixed bug with profiling when disabling a system and then closing
  the debugger.
- Debugger: Fixed bug with system list automatic sizing.

## [0.5.3] - 2022-07-05

### Added

- Added performance information to debugger.
- Add World inspector to debugger.

### Fixed

- Fix confusing error when a system yields inside a plasma context.

## [0.5.2] - 2022-07-01

### Fixed

- Fixed debugger panel not scrolling.
- In the debugger panel, the module name is now used when function is not named.

## [0.5.1] - 2022-06-30

### Fixed

- Fix custom debugger widgets not using the Plasma instance the user passed in.

## [0.5.0] - 2022-06-30

### Added

- Added Matter debugger.

### Changed

- Middleware now receive event name as a second parameter.

## [0.4.0] - 2022-06-25

### Changed

- Modifying the World while inside `World:query` can no longer cause iterator
  invalidation. All operations to World while inside a query are now safe. 🎉
  - If you aren't using `Loop`, you must call `World:optimizeQueries`
    periodically (e.g., every frame).
- If a system stops calling `queryChanged`, its internal storage will now be
  cleaned up. It is no longer a requirement that a system calls `queryChanged`
  forever.
- `Matter.merge` (an undocumented function) now only accepts two parameters.

### Fixed

- `replaceSystem` now correctly works when other systems reference a system
  being reloaded in their `after` table.
- If `spawnAt` is called with an entity ID that already exists, it now errors as
  expected.

## [0.3.0] - 2022-06-22

### Added

- Added `World:spawnAt` to spawn a new entity with a specified ID.
- Added `World:__iter` to allow iteration over all entities in the world the
  world from a for loop.
- Added `Loop:evictSystem(system)`, which removes a previously-scheduled system
  from the Loop. Evicting a system also cleans up any storage from hooks. This
  is intended to be used for hot reloading. Dynamically loading and unloading
  systems for gameplay logic is not recommended.
- Added `Loop:replaceSystem(before, after)`, which replaces an older version of
  a system with a newer version of the system. Internal system storage (which is
  used by hooks) will be moved to be associated with the new system. This is
  intended to be used for hot reloading.
- The Matter example game has been updated and adds support for both replication
  and hot reloading.

### Changed

- The first entity ID is now `1` instead of `0`.
- Events that have no systems scheduled to run on them are no longer skipped
  upon calling `Loop:begin`.

### Fixed

- Old event listeners created by `useEvent` were not properly disconnected when
  the passed event changed after having been already created. The event
  parameter passed to useEvent is not intended to be dynamically changed, so an
  warning has been added when this happens.

## [0.2.0] - 2022-06-04

### Added

- Added a second parameter to `Matter.component`, which allows specifying
  default component data.
- Add `QueryResult:snapshot` to convert a `QueryResult` into an immutable list.

### Changed

- `queryChanged` behavior has changed slightly: If an entity's storage was
  changed multiple times since your system last observed it, the `old` field in
  the `ChangeRecord` will be the last value your system observed the entity as
  having for that component, rather than what it was most recently changed from.
- World and Loop types are now exported.
- Matter now uses both `__iter` and `__call` for iteration over `QueryResult`.
- Improved many error messages from World methods, including passing nil values
  or passing a Component instead of a Component instance.
- Removed dependency on Llama.

### Fixed

- System error stack traces are now displayed properly.
- `World:clear()` now correctly resets internal changed storage used by
  `queryChanged`.

### Removed

- Additional query parameters to `queryChanged` have been removed.
  `queryChanged` now only takes one argument. If your code used these additional
  parameters, you can use `World:get(entityId, ComponentName)` to get a
  component, and use `continue` to skip iteration if it is not present.

## [0.1.2]- 2022-01-06

### Fixed

- Fix Loop sort by priority to sort properly.

## [0.1.1] - 2022-01-05

### Fixed

- Fix accidental system yield error message in Loop.

### Changed

- Accidentally yielding or erroring in a system does not prevent other systems
  from running.

## [0.1.0] - 2022-01-02

- Initial release

[unreleased]: https://github.com/matter-ecs/matter/compare/v0.8.4...HEAD
[0.8.4]: https://github.com/matter-ecs/matter/releases/tag/v0.8.4
[0.8.3]: https://github.com/matter-ecs/matter/releases/tag/v0.8.3
[0.8.2]: https://github.com/matter-ecs/matter/releases/tag/v0.8.2
[0.8.1]: https://github.com/matter-ecs/matter/releases/tag/v0.8.1
[0.8.0]: https://github.com/matter-ecs/matter/releases/tag/v0.8.0
[0.7.1]: https://github.com/matter-ecs/matter/releases/tag/v0.7.1
[0.7.0]: https://github.com/matter-ecs/matter/releases/tag/v0.7.0
[0.6.2]: https://github.com/matter-ecs/matter/releases/tag/v0.6.2
[0.6.1]: https://github.com/matter-ecs/matter/releases/tag/v0.6.1
[0.6.0]: https://github.com/matter-ecs/matter/releases/tag/v0.6.0
[0.5.3]: https://github.com/matter-ecs/matter/releases/tag/v0.5.3
[0.5.2]: https://github.com/matter-ecs/matter/releases/tag/v0.5.2
[0.5.1]: https://github.com/matter-ecs/matter/releases/tag/v0.5.1
[0.5.0]: https://github.com/matter-ecs/matter/releases/tag/v0.5.0
[0.4.0]: https://github.com/matter-ecs/matter/releases/tag/v0.4.0
[0.3.0]: https://github.com/matter-ecs/matter/releases/tag/v0.3.0
[0.2.0]: https://github.com/matter-ecs/matter/releases/tag/v0.2.0
[0.1.2]: https://github.com/matter-ecs/matter/releases/tag/v0.1.2
[0.1.1]: https://github.com/matter-ecs/matter/releases/tag/v0.1.1
[0.1.0]: https://github.com/matter-ecs/matter/releases/tag/v0.1.0
