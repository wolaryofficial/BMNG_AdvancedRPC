<template>
  <BngRow :label="label" :vertical="type !== 'switch'" no-focus-frame :disabled="disabled" :tooltip="hint || undefined" :data-field="field" :class="['arpc-field', { 'arpc-toggle': type === 'switch' }]">
    <BngSwitch v-if="type === 'switch'" :model-value="value" :aria-label="label" @update:model-value="emit('change', $event)" />
    <BngDropdown v-else-if="type === 'select'" :model-value="value" :items="options" :aria-label="label" @update:model-value="emit('change', $event)" />
    <textarea v-else-if="type === 'textarea'" v-bng-text-input :value="value" :aria-label="label" :rows="rows" :maxlength="maxlength" :readonly="readonly" :disabled="disabled" spellcheck="false" @input="emit('change', $event.target.value)" />
    <BngInput v-else :model-value="value" :type="type === 'number' ? 'number' : 'text'" :min="min" :max="max" :maxlength="maxlength" :readonly="readonly" :aria-label="label" :placeholder="placeholder" @update:model-value="emit('change', type === 'number' && $event !== '' ? Number($event) : $event)" />
  </BngRow>
</template>

<script setup>
import { BngRow, BngSwitch, BngDropdown, BngInput } from "@/common/components/base"
import { vBngTextInput } from "@/common/directives"
defineProps({
  label: String, field: String, value: [String, Number, Boolean], options: Array, hint: String,
  type: { type: String, default: "text" }, disabled: Boolean, readonly: Boolean,
  min: Number, max: Number, placeholder: String, rows: { type: Number, default: 4 }, maxlength: { type: Number, default: 512 },
})
const emit = defineEmits(["change"])
</script>

<style scoped>
.arpc-field { border-radius: 0.75rem; }
.arpc-field :deep(.bng-row-content) { min-width: 0; }
.arpc-field :deep(.bng-input), .arpc-field :deep(.bng-dropdown-container) { width: 100%; }
.arpc-toggle { align-items: center; }
.arpc-toggle :deep(.bng-row-label) { flex: 1 1 auto; }
.arpc-toggle :deep(.bng-row-content) { flex: 0 0 auto; padding-right: 0.25rem; }
textarea { box-sizing: border-box; width: 100%; resize: vertical; min-height: 4rem; padding: 0.65rem; border: 1px solid rgba(255,255,255,.25); border-radius: .35rem; background: rgba(0,0,0,.3); color: white; font: inherit; }
textarea:focus { outline: 2px solid #ff8b45; outline-offset: -2px; }
</style>
