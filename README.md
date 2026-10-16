# Water Pipes

**Water Pipes** is a Project Zomboid Build 42 mod for building networks that transport and distribute water, petrol, and other compatible liquids around a base.

[Read the official guide](https://carthon.github.io/WaterPipesModPZ/) · [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3739595559) · [Report a bug or suggest an improvement](https://github.com/carthon/WaterPipesModPZ/issues)

## Highlights

- Floor, vertical, and concealed pipes that form connected networks.
- Shared storage, pumps, municipal water, wells, rivers, and hydrants.
- Plumbing for fixtures and whole buildings.
- Pressure-aware routers, shut-off valves, and pressure gauges.
- Electric water purification, drip irrigation, and sprinklers.
- Petrol transport and automatic generator refuelling.
- Multiplayer support and configurable Sandbox and Mod Options.

The player guide is available in **English** and **Spanish**. The mod itself also includes a **Simplified Chinese** translation. Tutorials belong in the guide so this README can remain a concise project entry point.

## Installation

Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3739595559). For local development or testing, link `Contents/mods/WaterPipes` into the Project Zomboid mods directory; on Windows this is usually:

```text
C:\Users\<your_user>\Zomboid\mods\WaterPipes
```

## Documentation development

Python 3.13 is used in CI. Create and activate a virtual environment, then run:

```bash
python -m pip install --requirement requirements-docs.txt
mkdocs serve
```

Open `http://127.0.0.1:8000/WaterPipesModPZ/`. Run `mkdocs build --strict` for the same strict build used by CI.

English is the source language under `docs/en/`; Spanish pages live under `docs/es/` with matching filenames. Shared media belongs in `docs/assets/`. Keep unverified gameplay details clearly marked.

### Publishing with GitHub Pages

The `Documentation` workflow validates both language trees, builds the site, checks generated internal links, and uploads a Pages artifact. A repository administrator must enable it once:

1. Open **Settings → Pages** in GitHub.
2. Under **Build and deployment**, select **GitHub Actions** as the source.
3. Merge the documentation into `develop`, or run the workflow manually.

Pull requests build and validate the site but never deploy it. This change does not deploy to production.

## Contributing

Bug reports, feature requests, documentation corrections, translations, and pull requests are welcome through [GitHub Issues](https://github.com/carthon/WaterPipesModPZ/issues). Back up saves before testing mod changes.

## Credits

- **Tileset and sprite art** — [aariak_einherjer](https://steamcommunity.com/id/aariak_einherjer/) ([ArtStation](https://www.artstation.com/adrianechanizrol))
- **Sprite art and doc** — [xsleepykoalax](https://steamcommunity.com/id/xsleepykoalax/)
- **Simplified Chinese translation** — rakkasumi
- Everything else by Carthon.

## Licence

Copyright (c) 2026 Carthon. All rights reserved — see [LICENSE](LICENSE).

You may play with the mod, host it, read its source, and learn from it. Do not re-upload it or publish a modified version without permission, and credit **Water Pipes by Carthon** for permitted reuse. Some sprites derive from Project Zomboid assets and remain The Indie Stone's property. Project Zomboid is © The Indie Stone; this unofficial mod is not endorsed by or affiliated with The Indie Stone.
