package dev.peri.tweaks.mixin.create.elevator;

import com.simibubi.create.content.contraptions.AbstractContraptionEntity;
import com.simibubi.create.content.contraptions.Contraption;
import com.simibubi.create.content.contraptions.elevator.ElevatorColumn;
import com.simibubi.create.content.contraptions.elevator.ElevatorContactBlock;
import com.simibubi.create.content.contraptions.elevator.ElevatorContraption;
import dev.peri.tweaks.PerisTweaks;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.state.BlockState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/**
 * Brings back elevators already sent to a floor that doesn't exist (docs/fixes.md, "Create
 * elevators sink to Y 0"). ElevatorContactBlockEntityMixin stops new bad targets; this heals
 * the ones saved before it: when the column's target has no contact block, the elevator is
 * called to the contact nearest the cab, the same as a redstone call there.
 *
 * Each target is checked once, so the per-tick cost is one int compare.
 */
@Mixin(value = ElevatorContraption.class, remap = false)
public abstract class ElevatorContraptionMixin {
    @Shadow
    protected int contactYOffset;

    @Unique
    private int peris_tweaks$checkedTarget = Integer.MIN_VALUE;

    @Shadow
    public abstract ElevatorColumn.ColumnCoords getGlobalColumn();

    @Inject(method = "getCurrentTargetY", at = @At("HEAD"))
    private void peris_tweaks$healPhantomTarget(Level level, CallbackInfoReturnable<Integer> cir) {
        if (level.isClientSide()) {
            return;
        }
        ElevatorColumn.ColumnCoords coords = getGlobalColumn();
        ElevatorColumn column = ElevatorColumn.get(level, coords);
        if (column == null || !column.isTargetAvailable()) {
            return;
        }
        int target = column.getTargetedYLevel();
        if (target == peris_tweaks$checkedTarget) {
            return;
        }
        BlockPos targetPos = column.contactAt(target);
        if (!level.isLoaded(targetPos)) {
            return;
        }
        // A contact of this column, not one of a neighbouring column facing another way.
        if (level.getBlockState(targetPos).getBlock() instanceof ElevatorContactBlock
                && coords.equals(ElevatorContactBlock.getColumnCoords(level, targetPos))) {
            peris_tweaks$checkedTarget = target;
            return;
        }

        AbstractContraptionEntity cab = ((Contraption) (Object) this).entity;
        if (cab == null) {
            return;
        }
        double cabContactY = cab.getY() + contactYOffset;
        BlockPos nearest = null;
        for (BlockPos contact : column.getContacts()) {
            if (nearest == null || Math.abs(contact.getY() - cabContactY) < Math.abs(nearest.getY() - cabContactY)) {
                nearest = contact;
            }
        }
        if (nearest == null) {
            return; // Contacts not ticked in yet; look again next time.
        }
        BlockState state = level.getBlockState(nearest);
        if (state.getBlock() instanceof ElevatorContactBlock contactBlock) {
            PerisTweaks.LOGGER.info("Elevator at {} targeted Y {}, which has no contact; calling it to the floor at {}",
                    cab.blockPosition(), target, nearest);
            contactBlock.callToContactAndUpdate(column, state, level, nearest, false);
        }
    }
}
