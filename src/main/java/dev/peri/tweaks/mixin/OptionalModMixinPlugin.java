package dev.peri.tweaks.mixin;

import java.util.List;
import java.util.Map;
import java.util.Set;
import net.neoforged.fml.loading.LoadingModList;
import org.objectweb.asm.tree.ClassNode;
import org.spongepowered.asm.mixin.extensibility.IMixinConfigPlugin;
import org.spongepowered.asm.mixin.extensibility.IMixinInfo;

/**
 * Skips the patches for a mod that isn't installed, so every patched mod stays optional.
 * Patches live in a subpackage named after their mod; add a line here for each new one.
 */
public final class OptionalModMixinPlugin implements IMixinConfigPlugin {
    private static final String PACKAGE = "dev.peri.tweaks.mixin.";
    private static final Map<String, String> REQUIRED_MOD_BY_SUBPACKAGE = Map.of(
            PACKAGE + "create.", "create");

    @Override
    public boolean shouldApplyMixin(String targetClassName, String mixinClassName) {
        for (Map.Entry<String, String> entry : REQUIRED_MOD_BY_SUBPACKAGE.entrySet()) {
            if (mixinClassName.startsWith(entry.getKey())) {
                return LoadingModList.get().getModFileById(entry.getValue()) != null;
            }
        }
        return true;
    }

    @Override
    public void onLoad(String mixinPackage) {
    }

    @Override
    public String getRefMapperConfig() {
        return null;
    }

    @Override
    public void acceptTargets(Set<String> myTargets, Set<String> otherTargets) {
    }

    @Override
    public List<String> getMixins() {
        return null;
    }

    @Override
    public void preApply(String targetClassName, ClassNode targetClass, String mixinClassName, IMixinInfo mixinInfo) {
    }

    @Override
    public void postApply(String targetClassName, ClassNode targetClass, String mixinClassName, IMixinInfo mixinInfo) {
    }
}
