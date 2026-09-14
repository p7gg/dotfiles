import type { Plugin } from "@opencode-ai/plugin"

const PROVIDER_ID = "commandcode"
const ANTHROPIC_PROVIDER_ID = "commandcode-anthropic"
const BASE_URL = "https://api.commandcode.ai/provider/v1"
const DEFAULT_CONTEXT = 200_000
const DEFAULT_OUTPUT = 128_000

type Logger = (level: "info" | "warn" | "error", message: string) => void

type CommandCodeModel = {
  id: string
  name?: string
  context_length?: number
}

type ModelRegistration = {
  name: string
  limit: { context: number; output: number }
  reasoning?: boolean
  tool_call?: boolean
  options?: Record<string, unknown>
  variants?: Record<string, Record<string, unknown> & { disabled?: boolean }>
}

type ProviderConfig = {
  npm?: string
  name?: string
  options?: Record<string, unknown>
  models?: Record<string, ModelRegistration>
}

// Reasoning effort, overridable per-run without editing the plugin:
//   CMD_REASONING_EFFORT=xhigh opencode   (openai-compatible models)
//   CMD_THINKING_BUDGET=32000 opencode    (claude models via anthropic endpoint)
const REASONING_EFFORT = process.env.CMD_REASONING_EFFORT ?? "high"
const THINKING_BUDGET = Number(process.env.CMD_THINKING_BUDGET ?? 16_000) || 16_000

// Per-model reasoning efforts + capability, snapshotted from the
// command-code model catalog (command-code@1.49.1, refreshed 2026-09-06):
// https://unpkg.com/command-code@1.49.1/dist/bundled/command-code-knowledge/reference/models.md
// The Provider API (GET /provider/v1/models) returns only
// id/name/context_length — no reasoning metadata — so this table is the
// source of truth. Models omitted from BOTH maps are unknown: they keep
// the generic fallback (reasoning on, full variant set).
// Models in CAPABILITY with `true` but no EFFORTS entry are
// reasoning-capable without explicit levels — Command Code chooses the
// depth, so we advertise reasoning:true with NO variants/options.
const MODEL_EFFORTS: Record<string, readonly string[]> = {
  "deepseek/deepseek-v4-pro": ["high", "max"],
  "deepseek/deepseek-v4-flash": ["high", "max"],
  "deepseek/deepseek-v4-flash-vision-exp": ["high", "max"],
  "deepseek/deepseek-v4-flash-fast": ["low", "high", "max"],
  "moonshotai/Kimi-K3": ["low", "high", "max"],
  "z-ai/glm-5.3-flash": ["low", "high", "max"],
  "zai-org/GLM-5.3": ["low", "high", "max"],
  "zai-org/GLM-5.2": ["high", "max"],
  "Qwen/Qwen3.8-Max-0902": ["low", "medium", "xhigh"],
  "Qwen/Qwen3.8-Max": ["low", "medium", "xhigh"],
  "Qwen/Qwen3.8-27B": ["low", "medium", "xhigh"],
  "Qwen/Qwen3.8-Flash": ["low", "medium", "xhigh"],
  "tencent/hy4-preview": ["low", "medium", "high"],
  "claude-sonnet-5": ["low", "medium", "high", "xhigh", "max"],
  "claude-sonnet-4-6": ["low", "medium", "high", "xhigh", "max"],
  "claude-fable-5-1": ["low", "medium", "high", "xhigh", "max"],
  "claude-fable-5": ["low", "medium", "high", "xhigh", "max"],
  "claude-opus-5": ["low", "medium", "high", "xhigh", "max"],
  "claude-opus-4-8": ["low", "medium", "high", "xhigh", "max"],
  "claude-opus-4-7": ["low", "medium", "high", "xhigh", "max"],
  "gpt-6-astra": ["low", "medium", "high", "xhigh", "max"],
  "gpt-5.6-sol": ["low", "medium", "high", "xhigh", "max"],
  "gpt-5.6-terra": ["low", "medium", "high", "xhigh", "max"],
  "gpt-5.6-luna": ["low", "medium", "high", "xhigh", "max"],
  "gpt-5.5": ["low", "medium", "high", "xhigh"],
  "gpt-5.4": ["low", "medium", "high", "xhigh"],
  "gpt-5.3-codex": ["low", "medium", "high", "xhigh"],
  "gpt-5.4-mini": ["low", "medium", "high"],
  "google/gemini-3.8-flash": ["low", "medium", "high"],
  "google/gemini-3.7-flash": ["low", "medium", "high"],
  "google/gemini-3.6-flash": ["low", "medium", "high"],
  "google/gemini-3.5-flash": ["low", "medium", "high"],
  "google/gemini-3.5-flash-lite": ["low", "medium", "high"],
  "google/gemini-3.1-flash-lite": ["low", "medium", "high"],
  "sakana/fugu-ultra": ["high", "xhigh"],
  "meta/muse-spark-1.1": ["low", "medium", "high", "xhigh"],
  "meta/muse-spark-1.2": ["low", "medium", "high", "xhigh"],
  "meta/muse-spark-1.2-contributor": ["low", "medium", "high", "xhigh"],
  "meta/muse-spark-1.3": ["low", "medium", "high", "xhigh", "max"],
  "meta/muse-spark-1.3-contributor": ["low", "medium", "high", "xhigh"],
  "xai/grok-4.5": ["low", "medium", "high"],
  "xai/grok-4.6": ["low", "medium", "high", "xhigh"],
}

const MODEL_REASONING_CAPABILITY: Record<string, boolean> = {
  "claude-fable-5": true,
  "claude-fable-5-1": true,
  "claude-haiku-4-5-20251001": false,
  "claude-opus-4-7": true,
  "claude-opus-4-8": true,
  "claude-opus-5": true,
  "claude-sonnet-4-6": true,
  "claude-sonnet-5": true,
  "deepseek/deepseek-v4-flash": true,
  "deepseek/deepseek-v4-flash-fast": true,
  "deepseek/deepseek-v4-flash-vision-exp": true,
  "deepseek/deepseek-v4-pro": true,
  "google/gemini-3.1-flash-lite": true,
  "google/gemini-3.5-flash": true,
  "google/gemini-3.5-flash-lite": true,
  "google/gemini-3.6-flash": true,
  "google/gemini-3.7-flash": true,
  "google/gemini-3.8-flash": true,
  "gpt-5.3-codex": true,
  "gpt-5.4": true,
  "gpt-5.4-mini": true,
  "gpt-5.5": true,
  "gpt-5.6-luna": true,
  "gpt-5.6-sol": true,
  "gpt-5.6-terra": true,
  "gpt-6-astra": true,
  "meituan/LongCat-2.0:free": true,
  "meta/muse-spark-1.1": true,
  "meta/muse-spark-1.2": true,
  "meta/muse-spark-1.2-contributor": true,
  "meta/muse-spark-1.3": true,
  "meta/muse-spark-1.3-contributor": true,
  "MiniMaxAI/MiniMax-M2.5": false,
  "MiniMaxAI/MiniMax-M2.7": false,
  "MiniMaxAI/MiniMax-M3": true,
  "moonshotai/Kimi-K2.5": false,
  "moonshotai/Kimi-K2.6": false,
  "moonshotai/Kimi-K2.7-Code": true,
  "moonshotai/Kimi-K2.7-Code-Highspeed": true,
  "moonshotai/Kimi-K3": true,
  "nvidia/nemotron-3-ultra-550b-a55b": true,
  "poolside/laguna-s-2.1-free": true,
  "Qwen/Qwen3.6-Max-Preview": true,
  "Qwen/Qwen3.6-Plus": true,
  "Qwen/Qwen3.7-Flash": true,
  "Qwen/Qwen3.7-Max": true,
  "Qwen/Qwen3.7-Plus": true,
  "Qwen/Qwen3.8-27B": true,
  "Qwen/Qwen3.8-Flash": true,
  "Qwen/Qwen3.8-Max": true,
  "Qwen/Qwen3.8-Max-0902": true,
  "sakana/fugu-ultra": true,
  "stepfun/Step-3.5-Flash": true,
  "stepfun/Step-3.7-Flash": true,
  "tencent/hy3-paid": true,
  "tencent/hy4-preview": true,
  "thinkingmachines/inkling": true,
  "thinkingmachines/inkling-small": true,
  "xai/grok-4.5": true,
  "xai/grok-4.6": true,
  "xiaomi/mimo-v2.5": false,
  "xiaomi/mimo-v2.5-pro": false,
  "z-ai/glm-5.3-flash": true,
  "zai-org/GLM-5": false,
  "zai-org/GLM-5.1": false,
  "zai-org/GLM-5.2": true,
  "zai-org/GLM-5.2-Fast": false,
  "zai-org/GLM-5.3": true,
}

// Generic fallback for models in NEITHER map (new/unknown). "none" is
// deliberately excluded — CommandCode's reasoning_effort only accepts
// low|medium|high|xhigh|max and rejects anything else with HTTP 400.
const FALLBACK_EFFORTS: readonly string[] = ["low", "medium", "high", "xhigh", "max"]

function effortsForModel(id: string): readonly string[] | undefined {
  return MODEL_EFFORTS[id]
}

function pickDefaultEffort(efforts: readonly string[]): string {
  if (efforts.includes(REASONING_EFFORT)) return REASONING_EFFORT
  if (efforts.includes("high")) return "high"
  return efforts[Math.floor(efforts.length / 2)] ?? efforts[0] ?? "high"
}

// Budget tiers for Claude models on the anthropic endpoint, anchored on
// CMD_THINKING_BUDGET as the "high" tier.
function thinkingBudgetFor(effort: string): number {
  switch (effort) {
    case "low":
      return 8_000
    case "medium":
      return 12_000
    case "high":
      return THINKING_BUDGET
    case "xhigh":
      return Math.max(THINKING_BUDGET, 32_000)
    case "max":
      return Math.max(THINKING_BUDGET, 64_000)
    default:
      return THINKING_BUDGET
  }
}

function openaiVariantsFor(efforts: readonly string[]): Record<string, Record<string, unknown>> {
  return Object.fromEntries(efforts.map((effort) => [effort, { reasoningEffort: effort }]))
}

function anthropicVariantsFor(efforts: readonly string[]): Record<string, Record<string, unknown>> {
  return Object.fromEntries(
    efforts.map((effort) => [effort, { thinking: { type: "enabled", budgetTokens: thinkingBudgetFor(effort) } }]),
  )
}

// Promos with no signal in the id string — CommandCode's arbitrary,
// time-limited discounts. These can't be derived automatically and
// must be updated by hand when they change.
// Screenshot 2026-09-09: minimax-m3 2× usage ("Every credit goes 2× further"),
// mimo-v2.5 + mimo-v2.5-pro Up to 99% off ("Every dollar of credit goes further"),
// laguna-s-2.1-free free ("Requests on this model cost no credits", while capacity lasts),
// longcat-2.0:free free ("Requests on this model cost no credits", while it lasts),
// ling-3.0-flash-sante:free free ("is free, up to 100 requests a day", while it lasts),
// deepseek-v4.1-flash boosted credits ("$60 on GOAT ($40), $70 on Pro ($50)", through September 17, 2026).
const DEAL_LABELS: Record<string, string> = {
  "deepseek-v4.1-flash": "boosted credits, thru Sep 17",
  "minimax-m3": "2× usage",
  "mimo-v2.5": "Up to 99% off",
  "mimo-v2.5-pro": "Up to 99% off",
}

// Naming conventions CommandCode does apply consistently — checked
// before the manual map above.
type DealRule = {
  test: RegExp
  label: string
}

const DEAL_RULES: DealRule[] = [
  { test: /-free$/i, label: "free" },
  { test: /:free$/i, label: "free" },
]

const isSnapshot = (id: string) => /-\d{8}$/.test(id)

function modelKey(id: string): string {
  return id.split("/").pop() ?? id
}

function isClaude(key: string): boolean {
  return /^claude/i.test(key)
}

function dealLabel(key: string): string | undefined {
  for (const rule of DEAL_RULES) {
    if (rule.test.test(key)) return rule.label
  }
  return DEAL_LABELS[key.toLowerCase()]
}

async function discoverModels(log: Logger): Promise<CommandCodeModel[]> {
  try {
    const response = await fetch(`${BASE_URL}/models`)
    if (!response.ok) {
      await log("warn", `model discovery failed: HTTP ${response.status}`)
      return []
    }
    const json = (await response.json()) as { data?: CommandCodeModel[] }
    return Array.isArray(json.data) ? json.data : []
  } catch (error) {
    await log("warn", `model discovery failed: ${error instanceof Error ? error.message : error}`)
    return []
  }
}

export const CommandCodeModels = (async ({ client }) => {
  const log: Logger = async (level, message) => {
    const payload = { service: "commandcode", level, message }
    try {
      await client.app.log({ body: payload })
    } catch {
      try {
        await (client.app.log as unknown as (args: unknown) => Promise<void>)(payload)
      } catch {}
    }
  }

  return {
    config: async (config) => {
      const providers = (config.provider ??= {})

      const openai = (providers[PROVIDER_ID] ??= {
        npm: "@ai-sdk/openai-compatible",
        name: "CommandCode",
        options: { baseURL: BASE_URL },
      }) as ProviderConfig

      const anthropic = (providers[ANTHROPIC_PROVIDER_ID] ??= {
        npm: "@ai-sdk/anthropic",
        name: "CommandCode (Anthropic)",
        options: { baseURL: BASE_URL },
      }) as ProviderConfig

      const discovered = await discoverModels(log)
      if (discovered.length === 0) return

      let registered = 0
      for (const model of discovered) {
        if (isSnapshot(model.id)) continue

        const key = modelKey(model.id)
        const target = isClaude(key) ? anthropic : openai
        const label = dealLabel(key)

        // Register under the FULL id — the endpoint routes on the
        // provider-prefixed id (e.g. "minimax/minimax-m3-free"),
        // not the bare name. Stripping the prefix made every
        // slash-prefixed model fail with "not supported on this endpoint".
        const registrationId = model.id

        target.models ??= {}
        // `??=` preserves user overrides from opencode.json — a model the
        // user already configured (e.g. with custom options/variants) is
        // left untouched. Defaults below only apply to auto-discovered
        // entries, and can be tuned per-run via CMD_REASONING_EFFORT /
        // CMD_THINKING_BUDGET without editing this file.
        // Per https://opencode.ai/docs/models/#configure-models :
        // openai-compatible models take `options.reasoningEffort`,
        // anthropic models take `options.thinking`.
        const isAnthropicTarget = target === anthropic
        const efforts = effortsForModel(registrationId)
        const capability = MODEL_REASONING_CAPABILITY[registrationId]

        // reasoning:false models (Haiku 4.5, MiniMax M2.5/M2.7, Kimi
        // 2.5/2.6, MiMo, GLM-5/5.1/5.2-Fast): no options, no variants.
        if (capability === false) {
          target.models[registrationId] ??= {
            name: label ? `${model.name ?? key} (${label})` : (model.name ?? key),
            limit: {
              context: model.context_length ?? DEFAULT_CONTEXT,
              output: DEFAULT_OUTPUT,
            },
            reasoning: false,
            tool_call: true,
          }
        } else if (efforts ?? (capability === true)) {
          // Known efforts → one variant per supported level, default
          // clamped to the supported set. Capability-true without efforts
          // (Qwen 3.7-*, Kimi 2.7-Code, nemotron, inkling, LongCat, …) →
          // reasoning:true with NO options/variants, Command Code picks
          // the depth.
          const supported = efforts ?? []
          const defaultEffort = supported.length > 0 ? pickDefaultEffort(supported) : undefined
          target.models[registrationId] ??= {
            name: label ? `${model.name ?? key} (${label})` : (model.name ?? key),
            limit: {
              context: model.context_length ?? DEFAULT_CONTEXT,
              output: DEFAULT_OUTPUT,
            },
            reasoning: true,
            tool_call: true,
            ...(defaultEffort !== undefined
              ? {
                  options: isAnthropicTarget
                    ? { thinking: { type: "enabled", budgetTokens: thinkingBudgetFor(defaultEffort) } }
                    : { reasoningEffort: defaultEffort },
                  variants: isAnthropicTarget
                    ? anthropicVariantsFor(supported)
                    : openaiVariantsFor(supported),
                }
              : {}),
          }
        } else {
          // Unknown model (in neither map): generic fallback.
          const defaultEffort = pickDefaultEffort(FALLBACK_EFFORTS)
          target.models[registrationId] ??= {
            name: label ? `${model.name ?? key} (${label})` : (model.name ?? key),
            limit: {
              context: model.context_length ?? DEFAULT_CONTEXT,
              output: DEFAULT_OUTPUT,
            },
            reasoning: true,
            tool_call: true,
            options: isAnthropicTarget
              ? { thinking: { type: "enabled", budgetTokens: thinkingBudgetFor(defaultEffort) } }
              : { reasoningEffort: defaultEffort },
            variants: isAnthropicTarget
              ? anthropicVariantsFor(FALLBACK_EFFORTS)
              : openaiVariantsFor(FALLBACK_EFFORTS),
          }
        }
        registered++
      }

      await log("info", `registered ${registered} models`)
    },

    "chat.headers": async (_input, output) => {
      if (process.env.CMD_ZDR === "1") {
        output.headers["x-cmd-zdr"] = "1"
      }
    },
  }
}) satisfies Plugin

export default CommandCodeModels