import { lua } from "@/bridge"

export async function onLoad() {
  await lua.extensions.ui_pause_actions.unregisterModButton("custom-rpc-settings")
  const result = await lua.extensions.ui_pause_actions.registerModButton({
    id: "advanced-rpc-settings", tabId: "mods", label: "AdvancedRPC", icon: "wrench",
    componentName: "/ui/ui-vue/mods/AdvancedRPC/Settings.vue",
  })
  if (!result?.success) console.error("[AdvancedRPC] Settings registration failed", result?.reason)
}

export async function onUnload() {
  await lua.extensions.ui_pause_actions.unregisterModButton("advanced-rpc-settings")
}
