const AntiqueAtlasKeybindings = Java.loadClass("folk.sisby.antique_atlas.AntiqueAtlasKeybindings")
const AntiqueAtlasClient = Java.loadClass("folk.sisby.antique_atlas.client.AntiqueAtlasClient")

ClientEvents.tick(event => {
    const player = event.client.player
    if (!player) return

    // Only bypass in Creative
    if (!player.getAbilities().instabuild) return

    const key = AntiqueAtlasKeybindings.ATLAS_KEYMAPPING

    // If player pressed their configured Atlas key
    while (key.consumeClick()) {
        // Call the normal open logic
        AntiqueAtlasClient.openAtlas()
    }
})
