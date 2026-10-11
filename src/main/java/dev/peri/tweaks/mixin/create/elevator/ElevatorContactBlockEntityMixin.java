package dev.peri.tweaks.mixin.create.elevator;

import com.simibubi.create.content.contraptions.elevator.ElevatorColumn;
import com.simibubi.create.content.contraptions.elevator.ElevatorContactBlockEntity;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.entity.BlockEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Elevators sinking to Y 0 (docs/fixes.md, "Create elevators sink to Y 0").
 *
 * Each contact saves its column's target floor as ColumnTarget. Create gets this wrong twice:
 * a contact saved before its first tick drops the target it loaded (it waits in yTargetFromNBT,
 * which write() ignores), and a column without a target saves the unset value 0 as a real one.
 * Together they turn "no target" into "go to Y 0" two loads later.
 */
@Mixin(value = ElevatorContactBlockEntity.class, remap = false)
public abstract class ElevatorContactBlockEntityMixin {
    @Shadow
    public ElevatorColumn.ColumnCoords columnCoords;

    @Shadow
    private int yTargetFromNBT;

    @Inject(method = "write", at = @At("TAIL"))
    private void peris_tweaks$saveOnlyRealTargets(CompoundTag tag, HolderLookup.Provider registries, boolean clientPacket, CallbackInfo ci) {
        if (clientPacket) {
            return;
        }
        if (columnCoords == null) {
            // Not ticked yet: keep the target it loaded, still waiting to be applied.
            if (yTargetFromNBT != Integer.MIN_VALUE) {
                tag.putInt("ColumnTarget", yTargetFromNBT);
            }
            return;
        }
        Level level = ((BlockEntity) (Object) this).getLevel();
        ElevatorColumn column = level == null ? null : ElevatorColumn.get(level, columnCoords);
        if (column != null && !column.isTargetAvailable()) {
            tag.remove("ColumnTarget");
        }
    }
}
