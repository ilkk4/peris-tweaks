# Fixes

One section per fix: what players see, why it happens, what the patch changes, and how to
tell it worked. Newest first.

## Create elevators sink to Y 0

**Mod:** Create 6.0.10 · **Since:** 0.1.0 ·
**Patches:** `mixin/create/elevator/ElevatorContactBlockEntityMixin`, `ElevatorContraptionMixin`

**Symptom.** An elevator's rope runs down through solid rock and the cab is buried far below,
at the height where its contact would sit at Y 0. The floor displays still show the last real
floor. Calling that floor does nothing; calling any other floor brings the cab back.

**Cause.** The elevator column's target floor is not saved by itself. Every elevator contact in
the column saves it as `ColumnTarget`, and the column takes it back from them on load. Create
gets this wrong in two places in `ElevatorContactBlockEntity`:

1. `read()` parks the loaded target in `yTargetFromNBT` until `initialize()`, which runs on the
   contact's first tick. `write()` only writes the target from the live column. So when a chunk
   is loaded and saved again without ticking (the border ring past simulation distance, or a
   quick load and unload while flying past), every contact in it loses the target.
2. On the next load the column has no target. That alone is harmless, because the elevator holds
   still. But when the pulley re-attaches it marks the contacts changed, and `write()` saves
   `getTargetedYLevel()` without checking `isTargetAvailable()`. The unset value is 0.
3. On the load after that, every contact restores target Y 0. That is inside the elevator's
   range, and elevators ignore block collisions while moving, so the cab drives down through
   the ground to it.

Calling the floor shown on the displays does nothing because that contact still has
`CALLING=true` in its block state, and a redstone call is ignored while it is set.

**Fix.**
- `ElevatorContactBlockEntityMixin` (tail of `write`): a contact that hasn't ticked yet writes
  back the target it loaded, and a column without a target writes none. No more phantom 0.
- `ElevatorContraptionMixin` (head of `getCurrentTargetY`): heals worlds saved before the fix.
  When the column's target has no contact of this column (same X/Z and facing; since 0.1.1),
  it calls the elevator to the contact nearest the cab, the same as a redstone call there.
  A real floor at Y 0 is left alone: only a target without a contact is repaired. Each target is checked once (cached Y), so the
  steady per-tick cost is one int compare. It skips unloaded targets and contacts that haven't
  ticked in yet.

**Check.** The log shows `Elevator at ... targeted Y 0, which has no contact; calling it to the
floor at ...` once per healed elevator, and the cab rises to its lowest floor.
