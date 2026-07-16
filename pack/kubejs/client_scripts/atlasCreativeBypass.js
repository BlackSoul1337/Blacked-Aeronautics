ClientEvents.tick(event => {
    const mc = event.minecraft
    const player = mc.player
    if (!player) return

    // Only bypass in Creative
    if (!player.getAbilities().instabuild) return

    // Get AA4 keybinding directly
    const Keybindings = Java.loadClass("folk.sisby.antique_atlas.AntiqueAtlasKeybindings")
    const key = Keybindings.ATLAS_KEYMAPPING

    // If player pressed their configured Atlas key
    while (key.consumeClick()) {
        // Call the normal open logic
        const AtlasClient = Java.loadClass("folk.sisby.antique_atlas.client.AntiqueAtlasClient")
        AtlasClient.openAtlas()
    }
})