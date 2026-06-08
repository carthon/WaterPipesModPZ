# Changelog

All notable changes to Water Pipes are documented here. Dates are in YYYY-MM-DD.

## [0.2.0] - 2026-06-08

### Multiplayer
- **Pipe building now works in multiplayer.** Pipes were migrated to the Build 42 entity system,
  so placement is server-validated and no longer hangs forever on the building animation.
- **Plumbing is server-authoritative.** Connecting/disconnecting sinks and generators now runs on
  the server instead of the client, fixing client/server desync, duplicated fixtures stacking on a
  tile, and `sendObjectChange() can only be called on the server` errors.

### Added
- **Vertical pipe networks.** The vertical pipe (wall riser) is a single, rotatable build entry
  (North/West) and properly links floor pipes across the wall and between floors.
- **Network visualization.** Right-click any pipe → *Show pipe network* highlights the whole
  network: pipes in red, fluid-providing containers in green, and consumers (plumbed sinks,
  showers, toilets, generators) in blue. Auto-clears after a few seconds, or use *Hide pipe network*.
- **Any liquid can be drawn from a tap.** A plumbed tap now serves whatever single fluid its
  network holds (water, petrol, ...). Only Tainted Water is purified into clean Water at the tap;
  every other fluid comes out as-is.

### Changed
- **Taps prioritize their connected network.** A plumbed tap no longer pulls free city-mains water
  on top of its network source. When the water service is on, it serves the network fluid, not
  unlimited mains water.
- **Containers connect by exact tile.** A container only joins the network when a pipe sits on its
  own tile (no more loose adjacency). A vertical riser can be surrounded by horizontal pipes, but
  the object it feeds always needs a horizontal pipe on its tile.
- Completed Spanish/English translations (build category, new context-menu options).

### Fixed
- **Unplumbing restores the original state.** Disconnecting our system returns a fixture to exactly
  how it was before: a former city-mains tap goes back to unlimited water (if the service is on),
  and a fixture using a rain barrel keeps using it.
- Vertical connections that previously failed in single-player now connect correctly.

### Removed
- Legacy B41-style build menu and the old pipe build action (replaced by the entity system).

## [0.1.0]

- Initial release: buildable auto-connecting floor pipes and wall risers, fluid containers and
  fixtures sharing a single network, generator fuelling, any-fluid networks, bilingual UI.
