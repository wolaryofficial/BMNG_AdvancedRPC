<template>
  <BngGroupPanel class="advanced-rpc-settings-page">
    <template #header><BngCardHeading type="ribbon"><img class="arpc-logo" src="/mod_info/ADVANCEDRPC/icon.png" alt="AdvancedRPC logo" />AdvancedRPC</BngCardHeading></template>
    <div class="arpc-content">
      <div v-if="state.error" class="arpc-error" role="alert">
        {{ t(state.error) }}
        <div class="arpc-actions">
          <BngButton @click="retry">{{ t("Retry") }}</BngButton>
          <BngButton v-if="state.dirty" :disabled="state.busy" @click="model.discard()">{{ t("Discard unsaved edits") }}</BngButton>
        </div>
      </div>
      <p v-if="!state.ready" role="status">{{ t("Connecting to AdvancedRPC…") }}</p>
      <template v-else>
        <div class="arpc-connection" :data-state="state.status?.state" role="status">
          <span class="arpc-dot" :class="{ connected: ['native', 'ready'].includes(state.status?.state) }"></span>
          <span>{{ t(state.status?.message || 'Starting…') }}</span>
        </div>
        <nav class="arpc-tabs" :aria-label="t('AdvancedRPC settings')">
          <BngButton v-for="item in tabs" :key="item" :accent="tab === item ? 'main' : 'secondary'" :data-tab="item" @click="tab = item">{{ t(item) }}</BngButton>
        </nav>

        <template v-if="tab === 'General'">
          <BngGroupPanel :title="t('Interface and local player')">
            <Field label="Interface language" field="language" type="select" :value="config.language" :options="languages" @change="general('language', $event)" />
            <Field label="Local player to track" field="trackedPlayer" type="number" :value="config.trackedPlayer + 1" :min="1" :max="64" @change="general('trackedPlayer', Number($event) - 1)" />
            <p class="arpc-note">{{ t("Player 1 is the main player. In Split Screen, choose the player whose vehicle and telemetry should appear in Discord. Only one activity is published for your Discord account.") }}</p>
            <p class="arpc-note">{{ t('Joined local players: {players}', { players: (state.status?.localPlayers || [0]).map(value => value + 1).join(', ') }) }}</p>
            <p v-if="state.status?.preview?.variables?.map_id && !state.status?.playerAvailable" class="arpc-warning">{{ t("The selected player has no vehicle. Vehicle fields will use their fallback values.") }}</p>
          </BngGroupPanel>
          <BngGroupPanel :title="t('Connection')">
            <Field label="Enabled" field="enabled" type="switch" :value="config.enabled" @change="general('enabled', $event)" />
            <Field label="Connection mode" field="transport" type="select" :value="config.transport" :options="transports" @change="general('transport', $event)" />
            <template v-if="advanced">
              <Field label="Discord Application ID" field="applicationId" :value="config.applicationId" :maxlength="20" placeholder="Your application ID" @change="general('applicationId', $event)" />
              <p class="arpc-note">{{ t("Start AdvancedRPC Bridge.exe from the mod download. It runs in the Windows system tray and connects the game to Discord. Right-click its tray icon and enable Start with Windows for automatic startup. Keep the EXE in a permanent folder; if you move it, enable startup again from the new location.") }}</p>
              <details class="arpc-help"><summary>{{ t("Set up a Discord application") }}</summary>
                <p>{{ t("Open discord.com/developers/applications in your browser, create an application and copy its Application ID from General Information. Paste that public ID above. Keep the Discord desktop app running.") }}</p>
                <p>{{ t("Add images under Rich Presence → Art Assets, then use their keys in Images. Public HTTPS image URLs also work. No account token or client secret is needed.") }}</p>
              </details>
            </template>
            <Field label="Update interval (seconds)" field="updateInterval" type="number" :value="config.updateInterval" :min="1" :max="60" @change="general('updateInterval', $event)" />
            <p class="arpc-note">{{ t("Default: 5 seconds. Map, vehicle and career activity changes take priority. Rapid changes are combined to stay within Discord's update limit; Discord can delay what other users see.") }}</p>
            <Field label="Speed units" field="units" type="select" :value="config.units" :options="units" @change="general('units', $event)" />
            <div class="arpc-actions"><BngButton data-action="reconnect" @click="model.action('reconnect')">{{ t("Reconnect") }}</BngButton></div>
          </BngGroupPanel>
          <BngGroupPanel :title="t('Profile selection')">
            <Field label="Automatic profile rules" field="automatic" type="switch" :value="config.automatic" @change="general('automatic', $event)" />
            <Field :label="config.automatic ? 'Fallback profile' : 'Active profile'" field="selectedProfileId" type="select" :value="config.selectedProfileId" :options="profileOptions" @change="general('selectedProfileId', $event)" />
            <p class="arpc-note">{{ t(config.automatic ? 'The first matching rule wins. If nothing matches, the fallback profile is used.' : 'This profile stays active until you select another one.') }}</p>
          </BngGroupPanel>
        </template>

        <template v-if="tab === 'Profiles'">
          <BngGroupPanel :title="t('Your profiles')">
            <Field label="Edit profile" field="editProfile" type="select" :value="selected" :options="profileOptions" @change="selected = $event" />
            <Field v-if="profile" label="Profile name" field="name" :value="profile.name" :maxlength="80" @change="edit('name', $event)" />
            <div class="arpc-actions">
              <BngButton data-action="create" :disabled="state.busy" @click="profileAction('create')">{{ t("New") }}</BngButton>
              <BngButton data-action="duplicate" :disabled="state.busy" @click="profileAction('duplicate')">{{ t("Duplicate") }}</BngButton>
              <BngButton :disabled="state.busy || selectedIndex === 0" @click="profileAction('move', -1)">{{ t("Move up") }}</BngButton>
              <BngButton :disabled="state.busy || selectedIndex === config.profiles.length - 1" @click="profileAction('move', 1)">{{ t("Move down") }}</BngButton>
              <BngButton :disabled="state.busy || config.profiles.length < 2" data-action="delete" @click="confirmAction('delete')">{{ t(confirm === 'delete' ? 'Confirm delete' : 'Delete') }}</BngButton>
              <BngButton :disabled="state.busy" @click="confirmAction('profileReset')">{{ t(confirm === 'profileReset' ? 'Confirm reset' : 'Reset profile') }}</BngButton>
            </div>
          </BngGroupPanel>
          <BngGroupPanel :title="t('Ready presets')">
            <Field label="Preset" field="preset" type="select" :value="preset" :options="presetOptions" @change="preset = $event" />
            <Field label="Add an automatic rule" field="presetRule" type="switch" :value="presetRule" @change="presetRule = $event" />
            <p class="arpc-note">{{ t("Creates a new editable profile. Its rule is added above existing rules. Automatic rules must be enabled in General.") }}</p>
            <BngButton data-action="create-preset" :disabled="state.busy || config.profiles.length >= 50 || (presetRule && config.rules.length >= 100)" @click="createPreset">{{ t('Create from preset') }}</BngButton>
          </BngGroupPanel>
          <BngGroupPanel :title="t('Import / export')">
            <p class="arpc-note">{{ t("Profile JSON contains appearance settings only. Copy an export or paste a profile to import it as a new entry.") }}</p>
            <Field label="Profile JSON" field="profileJson" type="textarea" :value="jsonText" :maxlength="262144" :rows="6" @change="jsonText = $event" />
            <div class="arpc-actions">
              <BngButton data-action="export" @click="exportProfile">{{ t("Export selected") }}</BngButton>
              <BngButton data-action="import" :disabled="!jsonText || state.busy" @click="importProfile">{{ t("Import as new") }}</BngButton>
            </div>
          </BngGroupPanel>
        </template>

        <template v-if="['Text', 'Images', 'Buttons & timer'].includes(tab) && profile">
          <Field label="Editing profile" field="editProfile" type="select" :value="selected" :options="profileOptions" @change="selected = $event" />
          <p v-if="selected !== state.status?.profileId" class="arpc-note">{{ t("This profile is not currently active. Select it in General or assign an automatic rule.") }}</p>
        </template>

        <template v-if="tab === 'Text' && profile">
          <BngGroupPanel :title="t('Activity text')">
            <Field v-for="f in textFields" :key="f.key" :label="f.label" :field="f.key" :value="profile[f.key]" @change="edit(f.key, $event)" />
            <template v-if="advanced">
              <Field label="Activity name (empty uses application name)" field="activityName" :value="profile.activityName" @change="edit('activityName', $event)" />
              <Field label="Activity type" field="activityType" type="select" :value="profile.activityType" :options="activityTypes" @change="edit('activityType', $event)" />
              <Field label="Member-list status text" field="statusDisplay" type="select" :value="profile.statusDisplay" :options="statusTypes" @change="edit('statusDisplay', $event)" />
              <Field v-for="f in textLinks" :key="f.key" :label="f.label" :field="f.key" :value="profile[f.key]" placeholder="https://…" @change="edit(f.key, $event)" />
            </template>
            <p v-else class="arpc-note">{{ t("Custom activity names, activity types and clickable text are available in Custom Application mode.") }}</p>
          </BngGroupPanel>
          <BngGroupPanel :title="t('Rotating text')">
            <Field label="Rotate text" field="rotationEnabled" type="switch" :value="profile.rotationEnabled" @change="edit('rotationEnabled', $event)" />
            <template v-if="profile.rotationEnabled">
              <Field label="Rotation interval (seconds)" field="rotationSeconds" type="number" :value="profile.rotationSeconds" :min="15" :max="300" @change="edit('rotationSeconds', $event)" />
              <Field label="Details variants — one per line" field="detailsVariants" type="textarea" :value="profile.detailsVariants.join('\n')" :maxlength="16000" @change="edit('detailsVariants', lines($event))" />
              <Field label="State variants — one per line" field="stateVariants" type="textarea" :value="profile.stateVariants.join('\n')" :maxlength="16000" @change="edit('stateVariants', lines($event))" />
            </template>
          </BngGroupPanel>
          <BngGroupPanel :title="t('Variables')">
            <p class="arpc-note">{{ t("Use {variable} or {variable|fallback}. Missing values use the fallback or N/A. Select a field below, then click a variable to append it.") }}</p>
            <p class="arpc-note">{{ t("Career supports exploring, walking, missions, deliveries, tutorials and part shopping. Use {career_activity}, {career_money}, {career_beamxp}, {career_level} and {career_profile}, or select a career context in Rules.") }}</p>
            <Field label="Insert into" type="select" :value="insertTarget" :options="insertOptions" @change="insertTarget = $event" />
            <div class="arpc-variables"><BngButton v-for="(description, name) in state.variables" :key="name" accent="secondary" :title="t(description)" @click="edit(insertTarget, profile[insertTarget] + '{' + name + '}')">{{ '{' + name + '}' }}</BngButton></div>
          </BngGroupPanel>
        </template>

        <template v-if="tab === 'Images' && profile">
          <BngGroupPanel :title="t('Images and captions')">
            <p class="arpc-note">{{ t(advanced ? 'Use assets uploaded to your application or a public HTTPS image URL. BeamNG asset keys are not shared with your application.' : 'Use BeamNG asset keys, such as lvl_italy or lvl_utah, or a public HTTPS image URL. {map_asset} selects a supported map image automatically.') }}</p>
            <p class="arpc-note">{{ t("Paste a direct HTTPS link to an image, including PNG, JPEG, WebP or GIF. Captions appear when someone hovers over the image in Discord. Captions support variables such as {map} and {vehicle}; leave them empty to hide them.") }}</p>
            <Field v-for="f in imageFields" :key="f.key" :label="f.label" :field="f.key" :placeholder="f.placeholder || ''" :value="profile[f.key]" @change="edit(f.key, $event)" />
            <template v-if="advanced"><Field v-for="f in imageLinks" :key="f.key" :label="f.label" :field="f.key" :value="profile[f.key]" placeholder="https://…" @change="edit(f.key, $event)" /></template>
          </BngGroupPanel>
          <BngGroupPanel v-for="mapping in mappingGroups" :key="mapping.key" :title="t(mapping.title)">
            <p class="arpc-note">{{ t(mapping.note) }}</p>
            <div v-for="(row, index) in profile[mapping.key]" :key="index" class="arpc-subcard">
              <Field :label="mapping.label" :value="row.match" @change="arrayField(mapping.key, index, 'match', $event)" />
              <Field label="Image key or HTTPS URL" :value="row.image" @change="arrayField(mapping.key, index, 'image', $event)" />
              <BngButton accent="secondary" @click="removeRow(mapping.key, index)">{{ t("Remove mapping") }}</BngButton>
            </div>
            <BngButton :disabled="profile[mapping.key].length >= 100" @click="edit(mapping.key, [...profile[mapping.key], { match: '', image: '' }])">{{ t('Add mapping') }}</BngButton>
          </BngGroupPanel>
        </template>

        <BngGroupPanel v-if="['Images', 'Preview'].includes(tab) && profile" :title="t('Image URL check')">
          <p class="arpc-note">{{ t("Checks the resolved images for this profile and current map or vehicle. Asset keys cannot be checked in the game preview. A successful preview does not guarantee that Discord can fetch the image.") }}</p>
          <div class="arpc-actions">
            <BngButton data-action="check-images" :disabled="checkingImages" @click="checkImages">{{ checkingImages ? t('Checking…') : t('Check images') }}</BngButton>
            <BngButton data-action="retry-images" :disabled="checkingImages" @click="retryImages">{{ t("Retry images") }}</BngButton>
          </div>
          <div v-for="slot in ['large', 'small']" :key="slot" class="arpc-image-check" :data-image-check="slot" :data-result="imageChecks[slot]?.code">
            <strong>{{ t(slot === 'large' ? 'Large image' : 'Small image') }}</strong>
            <span role="status">{{ imageCheckText(imageChecks[slot]) }}</span>
          </div>
        </BngGroupPanel>

        <template v-if="tab === 'Buttons & timer' && profile">
          <p v-if="!advanced" class="arpc-note">{{ t("Buttons, Discord timers and party size require Custom Application mode. You can prepare these settings now; Native mode publishes text and images.") }}</p>
          <BngGroupPanel :title="t('Buttons')">
            <div v-for="(button, index) in profile.buttons" :key="index" class="arpc-subcard">
              <Field :label="t('Button {number} enabled', { number: index + 1 })" type="switch" :value="button.enabled" @change="arrayField('buttons', index, 'enabled', $event)" />
              <Field label="Label" :value="button.label" :maxlength="32" @change="arrayField('buttons', index, 'label', $event)" />
              <Field label="HTTPS URL" :value="button.url" placeholder="https://…" @change="arrayField('buttons', index, 'url', $event)" />
              <BngButton accent="secondary" @click="removeRow('buttons', index)">{{ t("Remove button") }}</BngButton>
            </div>
            <BngButton :disabled="profile.buttons.length >= 2" @click="edit('buttons', [...profile.buttons, { enabled: true, label: '', url: '' }])">{{ t('Add button') }}</BngButton>
          </BngGroupPanel>
          <BngGroupPanel :title="t('Timer')">
            <Field label="Timer mode" field="timerMode" type="select" :value="profile.timerMode" :options="timerTypes" @change="edit('timerMode', $event)" />
            <Field v-if="profile.timerMode === 'countdown'" label="Countdown duration (seconds)" field="countdownSeconds" type="number" :value="profile.countdownSeconds" :min="1" :max="604800" @change="edit('countdownSeconds', $event)" />
            <p class="arpc-note">{{ t("Timers keep their start time between activity updates. Countdown starts when the profile becomes active. BeamMP party size is shown automatically when both the player count and limit are available.") }}</p>
          </BngGroupPanel>
        </template>

        <template v-if="tab === 'Rules'">
          <BngGroupPanel :title="t('Automatic profile rules')">
            <Field label="Automatic rules enabled" field="automatic" type="switch" :value="config.automatic" @change="general('automatic', $event)" />
            <p class="arpc-note">{{ t("Rules are checked from top to bottom. Every condition in a rule must match. Map and vehicle filters use exact IDs; leave a filter empty to accept any value. Speed limits are always in km/h.") }}</p>
            <div v-for="(rule, index) in config.rules" :key="rule.id" class="arpc-subcard">
              <Field :label="t('Rule {number}', { number: index + 1 })" type="switch" :value="rule.enabled" @change="ruleField(index, 'enabled', $event)" />
              <Field label="Use profile" type="select" :value="rule.profileId" :options="profileOptions" @change="ruleField(index, 'profileId', $event)" />
              <Field label="Game context" type="select" :value="rule.context" :options="contextOptions" @change="ruleField(index, 'context', $event)" />
              <Field label="Map ID" :value="rule.map" placeholder="Any map" @change="ruleField(index, 'map', $event)" />
              <Field label="Vehicle model ID" :value="rule.vehicle" placeholder="Any vehicle" @change="ruleField(index, 'vehicle', $event)" />
              <div class="arpc-columns">
                <Field label="Minimum km/h" type="number" :value="rule.minSpeed" :min="0" @change="ruleField(index, 'minSpeed', $event)" />
                <Field label="Maximum km/h" type="number" :value="rule.maxSpeed" :min="0" @change="ruleField(index, 'maxSpeed', $event)" />
              </div>
              <Field label="Pause state" type="select" :value="rule.paused" :options="pauseOptions" @change="ruleField(index, 'paused', $event)" />
              <div class="arpc-actions">
                <BngButton :disabled="index === 0" @click="moveRule(index, -1)">{{ t("Move up") }}</BngButton>
                <BngButton :disabled="index === config.rules.length - 1" @click="moveRule(index, 1)">{{ t("Move down") }}</BngButton>
                <BngButton accent="secondary" @click="removeRule(index)">{{ t("Remove rule") }}</BngButton>
              </div>
            </div>
            <BngButton data-action="add-rule" :disabled="config.rules.length >= 100" @click="addRule">{{ t('Add rule') }}</BngButton>
          </BngGroupPanel>
        </template>

        <template v-if="tab === 'Preview'">
          <Field label="Preview profile" field="previewProfile" type="select" :value="selected" :options="profileOptions" @change="selected = $event" />
          <div v-if="displayPreview" class="arpc-presence">
            <div class="arpc-presence-type">{{ presenceType }}</div>
            <div class="arpc-card-body">
              <div class="arpc-art">
                <img v-if="largePreviewUrl && !imageError" :key="'large-' + imageEpoch" :src="largePreviewUrl" :title="displayPreview.activity.assets?.large_text" :alt="t('Large image')" referrerpolicy="no-referrer" @error="imageError = true" />
                <div v-else class="arpc-placeholder" :title="displayPreview.activity.assets?.large_text">{{ displayPreview.activity.assets?.large_image ? 'RPC' : 'B' }}</div>
                <img v-if="smallPreviewUrl && !smallImageError" :key="'small-' + imageEpoch" class="arpc-small-image" :src="smallPreviewUrl" :title="displayPreview.activity.assets?.small_text" :alt="t('Small image')" referrerpolicy="no-referrer" @error="smallImageError = true" />
                <div v-else-if="displayPreview.activity.assets?.small_image" class="arpc-small-image arpc-small-placeholder" :title="displayPreview.activity.assets?.small_text">S</div>
              </div>
              <div class="arpc-presence-text">
                <strong>{{ displayPreview.activity.name || (advanced ? t('Your Discord application') : 'BeamNG.drive') }}</strong>
                <span v-if="displayPreview.activity.details">{{ displayPreview.activity.details }}</span>
                <span v-if="displayPreview.activity.state">{{ displayPreview.activity.state }}</span>
                <span v-if="advanced && displayPreview.activity.timestamps" class="arpc-muted">{{ t(displayPreview.activity.timestamps.end ? 'Countdown timer' : 'Elapsed timer') }}</span>
                <span v-if="advanced && displayPreview.activity.party" class="arpc-muted">{{ displayPreview.activity.party.size.join(' / ') }} {{ t('players') }}</span>
              </div>
            </div>
            <div v-if="advanced" class="arpc-preview-buttons"><span v-for="button in displayPreview.activity.buttons || []" :key="button.label">{{ button.label }}</span></div>
          </div>
          <p v-if="imageError || smallImageError" class="arpc-warning">{{ t("BeamNG could not display an external image in this preview. Discord loads images independently; this does not mean Discord rejected the URL. Use a public, direct HTTPS image URL.") }}</p>
          <p class="arpc-note">{{ t("Preview uses current game data. Hover over either image or placeholder to see its caption. BeamNG may block external image previews. Discord controls the final layout. Viewing a profile does not activate it.") }}</p>
          <div v-for="warning in displayPreview?.warnings || []" :key="warning" class="arpc-warning">{{ t(warning) }}</div>
          <BngGroupPanel :title="t('Connection and live data')">
            <p class="arpc-note">{{ t('Active profile') }}: <strong>{{ state.status?.profileName || '—' }}</strong><br />
              {{ t('Last submitted') }}: {{ time(state.status?.lastSentAt) }}<br />
              {{ t('Discord acknowledgement') }}: {{ t(advanced ? (state.status?.acknowledged ? 'Current activity accepted' : 'Not yet confirmed') : 'Not exposed by the native BeamNG API') }}
            </p>
            <dl class="arpc-values"><template v-for="(description, name) in state.variables" :key="name"><dt>{{ '{' + name + '}' }}</dt><dd>{{ displayPreview?.variables?.[name] ?? 'N/A' }}</dd></template></dl>
            <details class="arpc-help"><summary>{{ t("Outgoing activity") }}</summary><pre>{{ JSON.stringify(advanced ? displayPreview?.activity : displayPreview?.nativeActivity, null, 2) }}</pre></details>
          </BngGroupPanel>
        </template>

        <div class="arpc-footer">
          <BngButton class="no-focus-frame" :disabled="state.busy" data-action="reset-all" @click="confirmAction('all')">{{ t(confirm === 'all' ? 'Confirm reset all' : 'Reset defaults') }}</BngButton>
          <span role="status">{{ t(state.busy ? 'Saving…' : state.dirty ? 'Unsaved changes' : !state.saved ? 'Applied, not saved to disk' : 'Changes save automatically') }}</span>
        </div>
      </template>
      <div class="arpc-meta"><span class="arpc-credit">made by wolary (w0kx)</span><span class="arpc-version">v{{ VERSION }}</span></div>
    </div>
  </BngGroupPanel>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, provide, reactive, ref, watch } from "vue"
import { BngGroupPanel, BngCardHeading, BngButton } from "@/common/components/base"
import { useBridge } from "@/bridge"
import { runRaw, serialize } from "@/bridge/libs/Lua.js"
import Field from "./Field.vue"
import { VERSION, clone, createSettingsModel } from "./settingsModel.js"
import { resolveLanguage, translate, contextLabel } from "./i18n.js"
import { checkImage } from "./imageValidation.js"

const { events } = useBridge()
const state = reactive({ ready: false, busy: false, dirty: false, saved: true, error: "", config: null, revision: 0, variables: {}, contexts: [], presets: [], gameLanguage: 'en', status: null })
const language = computed(() => resolveLanguage(state.config?.language, state.gameLanguage))
const t = (text, values) => translate(text, language.value, values)
provide('advancedRPCTranslate', t)
const tab = ref('General'), selected = ref('automatic'), jsonText = ref(''), confirm = ref(''), insertTarget = ref('details')
const displayPreview = ref(null), imageError = ref(false)
const preset = ref('career'), presetRule = ref(true)
const checkingImages = ref(false), imageChecks = ref({}), imageEpoch = ref(0)
const tabs = ['General', 'Profiles', 'Text', 'Images', 'Buttons & timer', 'Rules', 'Preview']
const options = pairs => computed(() => pairs.map(([value, label]) => ({ value, label: t(label) })))
const languages = options([['auto', 'Use game language'], ['en', 'English'], ['ru', 'Русский']])
const transports = options([['native', 'BeamNG Native'], ['custom', 'Custom Application']])
const units = options([['game', 'Use game settings'], ['metric', 'Metric (km/h)'], ['imperial', 'Imperial (mph)']])
const activityTypes = options([[0, 'Playing'], [2, 'Listening'], [3, 'Watching'], [5, 'Competing']])
const statusTypes = options([[0, 'Application name'], [1, 'State'], [2, 'Details']])
const timerTypes = options([['hidden', 'Hidden'], ['session', 'Session elapsed'], ['map', 'Map elapsed'], ['profile', 'Profile elapsed'], ['countdown', 'Countdown']])
const pauseOptions = options([['any', 'Any'], ['yes', 'Paused'], ['no', 'Running']])
const textFields = [{ key: 'details', label: 'Details — first line' }, { key: 'state', label: 'State — second line' }]
const textLinks = [{ key: 'detailsUrl', label: 'Details link' }, { key: 'stateUrl', label: 'State link' }]
const imageFields = [{ key: 'largeImage', label: 'Large image URL or asset key', placeholder: 'https://example.com/image.png' }, { key: 'largeText', label: 'Large image caption (on hover)' }, { key: 'smallImage', label: 'Small image URL or asset key', placeholder: 'https://example.com/icon.png' }, { key: 'smallText', label: 'Small image caption (on hover)' }]
const imageLinks = [{ key: 'largeUrl', label: 'Large image click destination (optional)' }, { key: 'smallUrl', label: 'Small image click destination (optional)' }]
const insertOptions = computed(() => [...textFields, ...imageFields].map(f => ({ value: f.key, label: t(f.label) })))
const mappingGroups = [
  { key: 'mapImages', title: 'Map images', label: 'Map ID', note: 'Overrides the large image for an exact map ID, such as italy or west_coast_usa.' },
  { key: 'vehicleImages', title: 'Vehicle images', label: 'Vehicle model ID', note: 'Overrides the small image for an exact model ID, including modded vehicles.' },
]
const config = computed(() => state.config)
const advanced = computed(() => config.value?.transport === 'custom')
const profileOptions = computed(() => config.value?.profiles.map(p => ({ value: p.id, label: p.name })) || [])
const profile = computed(() => config.value?.profiles.find(p => p.id === selected.value))
const selectedIndex = computed(() => config.value?.profiles.findIndex(p => p.id === selected.value) ?? -1)
const contextOptions = computed(() => state.contexts.map(value => ({ value, label: t(contextLabel(value)) })))
const presetOptions = computed(() => state.presets.map(value => ({ value: value.id, label: t(value.name) })))
const largePreviewUrl = computed(() => url(displayPreview.value?.activity.assets?.large_image))
const smallPreviewUrl = computed(() => url(displayPreview.value?.activity.assets?.small_image))
const smallImageError = ref(false)
const presenceType = computed(() => activityTypes.value.find(x => x.value === (advanced.value ? displayPreview.value?.activity.type : 0))?.label.toUpperCase() || t('Playing').toUpperCase())
const allowedMethods = new Set(['getSettings', 'getStatus', 'setSettingsFromUI', 'profileAction', 'exportProfile', 'importProfile', 'resetDefaults', 'retrySave', 'getPreview', 'reconnect'])

async function call(method, args) {
  if (!allowedMethods.has(method)) throw new Error('Unknown controller method.')
  let timeout
  try {
    const command = `(function() local m=rawget(extensions,'advancedRPC') if not m then return {error="Enable AdvancedRPC in Mod Manager, then retry."} end return m.${method}(${args === undefined ? '' : serialize(args)}) end)()`
    return await Promise.race([runRaw(command), new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('AdvancedRPC did not respond. Retry the operation.')), 5000) })])
  } finally { clearTimeout(timeout) }
}
const model = createSettingsModel(state, call)
const general = (key, value) => model.edit({ general: { [key]: value } })
const edit = (key, value) => model.edit({ profiles: { [selected.value]: { [key]: value } } })
const lines = text => text.split(/\r?\n/).filter(line => line.trim())
const time = value => value ? new Date(value * 1000).toLocaleTimeString(language.value) : t('Not sent')
const url = value => typeof value === 'string' && /^https:\/\//i.test(value) ? value : ''

function arrayField(key, index, field, value) { const rows = clone(profile.value[key]); rows[index][field] = value; edit(key, rows) }
function removeRow(key, index) { edit(key, profile.value[key].filter((_, i) => i !== index)) }
function ruleField(index, key, value) { const rules = clone(config.value.rules); rules[index][key] = value; model.edit({ rules }) }
function removeRule(index) { model.edit({ rules: config.value.rules.filter((_, i) => i !== index) }) }
function moveRule(index, direction) { const rules = clone(config.value.rules); [rules[index], rules[index + direction]] = [rules[index + direction], rules[index]]; model.edit({ rules }) }
function addRule() {
  model.edit({ rules: [...config.value.rules, { id: 'rule-' + Date.now().toString(36) + '-' + (++ruleCounter), enabled: true, profileId: selected.value, context: 'any', map: '', vehicle: '', minSpeed: '', maxSpeed: '', paused: 'any' }] })
}
let ruleCounter = 0, confirmTimer, previewRequest = 0, disposed = false, imageController, imageRequest = 0
async function createPreset() {
  const result = await model.action('profileAction', { action: 'preset', presetId: preset.value, withRule: presetRule.value })
  if (result?.selectedId) selected.value = result.selectedId
}
async function profileAction(action, direction) {
  const result = await model.action('profileAction', { action, id: selected.value, direction })
  if (result?.selectedId) selected.value = result.selectedId
}
async function exportProfile() { const result = await model.action('exportProfile', { id: selected.value }); if (result?.json) jsonText.value = JSON.stringify(JSON.parse(result.json), null, 2) }
async function importProfile() { const result = await model.action('importProfile', { json: jsonText.value }); if (result?.selectedId) selected.value = result.selectedId }
async function confirmAction(action) {
  if (confirm.value !== action) { confirm.value = action; clearTimeout(confirmTimer); confirmTimer = setTimeout(() => { confirm.value = '' }, 5000); return }
  confirm.value = ''
  if (action === 'all') { await model.action('resetDefaults'); selected.value = config.value.selectedProfileId }
  else await profileAction(action === 'profileReset' ? 'reset' : action)
}
async function retry() { if (!state.ready) await model.load(); else if (state.dirty) await model.flush(); else await model.action('retrySave') }
async function refreshPreview() {
  if (!state.ready || !['Preview', 'Images'].includes(tab.value) || disposed) return
  const id = ++previewRequest
  try { const result = await call('getPreview', { profileId: selected.value }); if (!disposed && id === previewRequest && result?.activity) displayPreview.value = result } catch (error) { state.error = error.message }
}
function acceptSettings(result) { model.accept(result) }
function acceptStatus(result) { state.status = result; void refreshPreview() }
function resetImageChecks() {
  imageController?.abort()
  imageRequest++
  imageChecks.value = {}
  checkingImages.value = false
}
async function checkImages() {
  resetImageChecks()
  let request = imageRequest
  const profileId = selected.value
  checkingImages.value = true
  try {
    if (!await model.flush() || disposed || request !== imageRequest) return
    const resolved = await call('getPreview', { profileId })
    if (disposed || request !== imageRequest || !resolved?.activity) return
    displayPreview.value = resolved
    await nextTick()
    if (disposed || selected.value !== profileId || !['Images', 'Preview'].includes(tab.value)) return
    request = imageRequest
    checkingImages.value = true
    const controller = new AbortController()
    imageController = controller
    await Promise.all(['large', 'small'].map(async slot => {
      const result = await checkImage(resolved.imageSources?.[slot] ?? resolved.activity.assets?.[slot + '_image'] ?? '', config.value.transport, { signal: controller.signal })
      if (!disposed && request === imageRequest) imageChecks.value = { ...imageChecks.value, [slot]: result }
    }))
  } catch (error) { if (!disposed && request === imageRequest) state.error = error.message }
  finally { if (request === imageRequest) checkingImages.value = false }
}
async function retryImages() {
  imageEpoch.value++
  imageError.value = smallImageError.value = false
  await checkImages()
}
function imageCheckText(result) {
  if (!result) return t('Not checked')
  const messages = {
    empty: 'No image set.', asset: 'Asset key: {source}. Check its availability in Discord.',
    invalid: 'Use a direct HTTPS URL without spaces or credentials.', too_long: 'The image source exceeds the {limit}-byte limit for this connection mode.',
    loaded: 'Image loaded: {width} × {height}.', http_error: 'The server returned HTTP {status}.',
    not_image: 'The URL returned {type}, not an image.', timeout: 'The check timed out. Retry or use another image host.',
    unavailable: 'The image could not be loaded. The URL may be unavailable or blocked by BeamNG. Discord loads it independently.',
    blocked: 'BeamNG blocks external URL checks. The link format is valid; check the image in Discord.',
    cancelled: 'Check cancelled.',
  }
  return t(messages[result.code] || 'Not checked', result)
}
watch(() => config.value?.profiles.map(p => p.id).join(','), () => { if (config.value && !profile.value) selected.value = config.value.selectedProfileId })
watch([tab, selected, () => state.revision], refreshPreview)
watch(largePreviewUrl, () => { imageError.value = false })
watch(smallPreviewUrl, () => { smallImageError.value = false })
watch([selected, () => config.value?.transport, () => JSON.stringify(profile.value && [profile.value.largeImage, profile.value.smallImage, profile.value.mapImages, profile.value.vehicleImages])], resetImageChecks)
watch(() => JSON.stringify(displayPreview.value?.imageSources), resetImageChecks)
watch(tab, value => { if (!['Images', 'Preview'].includes(value)) resetImageChecks() })
onMounted(() => { events.on('AdvancedRPCSettings', acceptSettings); events.on('AdvancedRPCStatus', acceptStatus); void model.load() })
onBeforeUnmount(() => { disposed = true; imageController?.abort(); clearTimeout(confirmTimer); events.off('AdvancedRPCSettings', acceptSettings); events.off('AdvancedRPCStatus', acceptStatus); void model.dispose() })
</script>

<style scoped>
.arpc-logo { width: 4rem; height: 2.7rem; object-fit: contain; vertical-align: middle; margin-right: 0.7rem; border-radius: 0.35rem; }
.advanced-rpc-settings-page { width: 100%; min-width: 0; max-height: calc(100vh - 8rem); overflow: hidden; }
.arpc-content { min-height: 0; overflow-y: auto; padding: .5rem; }
.arpc-content, .arpc-content :deep(*) { user-select: text; -webkit-user-select: text; }
.arpc-content :deep(.bng-group-panel) { margin-bottom: .65rem; }
.arpc-content :deep(.bng-row-vertical .bng-row-label) { width: 100%; }
.arpc-connection { display: flex; align-items: center; gap: .6rem; margin: .4rem .5rem .9rem; font-size: .85rem; color: rgba(255,255,255,.75); }
.arpc-dot { width: .5rem; height: .5rem; border-radius: 50%; flex: 0 0 .5rem; background: #b99568; }
.arpc-dot.connected { background: #85ba7b; }
.arpc-tabs, .arpc-actions { display: flex; gap: .35rem; flex-wrap: wrap; margin: .4rem 0 .65rem; }
.arpc-tabs :deep(button) { font-size: .8rem; min-width: 0; }
.arpc-error { padding: .75rem; margin-bottom: .75rem; border-radius: .75rem; background: #713a25; overflow-wrap: anywhere; }
.arpc-note { margin: .65rem .5rem; font-size: .82rem; line-height: 1.5; color: rgba(255,255,255,.62); }
.arpc-help { margin: .75rem .5rem; font-size: .85rem; line-height: 1.5; }
.arpc-help summary { cursor: pointer; color: #ffae73; }
.arpc-help p { color: rgba(255,255,255,.72); }
.arpc-subcard { border: 1px solid rgba(255,255,255,.12); border-radius: .65rem; margin: .6rem 0; padding: .5rem; }
.arpc-columns { display: grid; grid-template-columns: 1fr 1fr; gap: .4rem; }
.arpc-variables { display: flex; flex-wrap: wrap; gap: .25rem; padding: .4rem; }
.arpc-variables :deep(button) { font: .75rem monospace; }
.arpc-presence { padding: 1rem; margin: .75rem .5rem; background: #202127; border: 1px solid #34353b; border-radius: .8rem; }
.arpc-presence-type { font-size: .7rem; letter-spacing: .06em; font-weight: 700; margin-bottom: .9rem; color: #c1c2cc; }
.arpc-card-body { display: flex; gap: .85rem; align-items: flex-start; }
.arpc-art { position: relative; width: 5rem; height: 5rem; flex: 0 0 5rem; }
.arpc-art > img, .arpc-placeholder { width: 5rem; height: 5rem; object-fit: cover; border-radius: .5rem; }
.arpc-placeholder { display: flex; align-items: center; justify-content: center; color: #ffae73; background: #363039; font-weight: 800; font-size: 1.5rem; }
.arpc-art .arpc-small-image { position: absolute; width: 1.8rem; height: 1.8rem; right: -.35rem; bottom: -.25rem; border: 3px solid #202127; border-radius: 50%; }
.arpc-small-placeholder { display: grid; place-items: center; background: #5865f2; color: white; font-size: .8rem; }
.arpc-presence-text { display: flex; flex-direction: column; gap: .25rem; font-size: .85rem; overflow-wrap: anywhere; min-width: 0; }
.arpc-presence-text strong { font-size: .95rem; }
.arpc-muted { color: #a5a6af; font-size: .75rem; }
.arpc-preview-buttons { display: grid; gap: .4rem; margin-top: .9rem; }
.arpc-preview-buttons span { padding: .5rem; border-radius: .4rem; background: #3a3b42; font-size: .8rem; text-align: center; }
.arpc-values { display: grid; grid-template-columns: auto 1fr; gap: .4rem .8rem; font-size: .78rem; padding: .5rem; }
.arpc-values dt { color: #ffae73; font-family: monospace; }
.arpc-values dd { margin: 0; overflow-wrap: anywhere; }
.arpc-warning { margin: .5rem; padding: .5rem .7rem; font-size: .8rem; background: rgba(164,104,44,.2); border-radius: .4rem; }
.arpc-image-check { display: grid; grid-template-columns: 7rem 1fr; gap: .5rem; margin: .65rem .5rem; font-size: .82rem; overflow-wrap: anywhere; }
.arpc-image-check[data-result="loaded"] { color: #acd79b; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; font-size: .75rem; max-height: 20rem; overflow-y: auto; }
.arpc-footer { display: flex; align-items: center; justify-content: space-between; gap: .75rem; flex-wrap: wrap; margin-top: .8rem; }
.arpc-footer span { font-size: .8rem; color: rgba(255,255,255,.6); }
.arpc-meta { display: flex; align-items: center; justify-content: space-between; gap: .75rem; margin: .75rem .5rem 0; }
.arpc-credit { font-size: .65rem; color: rgba(255,255,255,.12); }
.arpc-version { font-size: .75rem; color: rgba(255,255,255,.45); white-space: nowrap; }
@media (max-width: 700px) { .arpc-columns { grid-template-columns: 1fr; } .arpc-tabs :deep(button) { font-size: .72rem; } }
</style>
