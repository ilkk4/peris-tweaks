# Peri's Tweaks

The home for small fixes to other mods in the pack: bugs, not features. Features belong in
Living Villages (`D:\World Restore\living-villages`) or Peri's Overhaul
(`D:\Minecraft Mods\peris-overhaul`).

- Live pack: `D:\CurseForge\Instances\Create Long Con` (mods, logs, `saves/world`).
- NeoForge 21.1.250, MC 1.21.1, ModDevGradle, Parchment mappings, JDK 21.
- Package `dev.peri.tweaks`, mod id `peris_tweaks`.

## Adding a fix

1. Find the cause in the real code first. Decompile the pack's exact jar (Vineflower is in the
   Gradle cache) and, when you can, confirm it against the save's NBT before patching.
2. Put the mixin in `mixin/<modid>/...`, add it to `peris_tweaks.mixins.json`, and map the
   subpackage to its mod id in `OptionalModMixinPlugin`, so the patch is skipped when the mod
   is missing.
3. Add the mod to `gradle.properties` (Curse Maven `curse.maven:<slug>-<project>:<file>`, file
   id from the pack's `minecraftinstance.json`) as `compileOnly`, plus an optional dependency
   in `neoforge.mods.toml`.
4. Inject as narrowly as possible (`HEAD`/`TAIL`, no overwrites). Performance first: event
   driven, cheap early-outs, no per-tick scans. Prefix unique members `peris_tweaks$`.
5. If the bug already damaged saves, add a heal that repairs them on load, and log one line
   per repair.
6. Write a section in `docs/fixes.md` (symptom, cause, fix, how to check) and a row in the
   README table.

## Ship

```
powershell -File tools/ship.ps1 -Version x.y.z -Message "x.y.z: what it fixes"
```

Backup check, build, jar swap into the pack's mods folder, commit, and push if there's a
remote. It stops at the first failure.
