package dev.peri.tweaks;

import com.mojang.logging.LogUtils;
import net.neoforged.fml.common.Mod;
import org.slf4j.Logger;

/** Small fixes for the mods in Peri's pack. Every fix is a mixin; see docs/fixes.md. */
@Mod(PerisTweaks.MOD_ID)
public final class PerisTweaks {
    public static final String MOD_ID = "peris_tweaks";
    public static final Logger LOGGER = LogUtils.getLogger();
}
