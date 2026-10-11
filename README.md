# Peri's Tweaks

Small fixes for the mods in Peri's pack (NeoForge 21.1.250, Minecraft 1.21.1). Each fix is a
mixin into the mod it fixes, and it only applies when that mod is installed.

| Fix | Mod |
|---|---|
| [Create elevators sink to Y 0](docs/fixes.md#create-elevators-sink-to-y-0) | Create 6.0.10 |

## Build

```
gradlew build
```

The jar lands in `build/libs/`. Patched mods come from Curse Maven at the pack's exact versions
(`gradle.properties`), so any checkout builds.
