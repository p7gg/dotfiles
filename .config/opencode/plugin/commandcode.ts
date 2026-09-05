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

type ProviderConfig = {
  npm?: string
  name?: string
  options?: Record<string, unknown>
  models?: Record<string, { name: string; limit: { context: number; output: number } }>
}

// Promos with no signal in the id string — CommandCode's arbitrary,
// time-limited discounts. These can't be derived automatically and
// must be updated by hand when they change.
// Screenshot 2026-09-02: minimax-m3 2× usage ("Every credit goes 2× further"),
// mimo-v2.5 + mimo-v2.5-pro up to 99% off ("Every dollar of credit goes further"),
// laguna-s-2.1-free free ("Requests on this model cost no credits", while capacity lasts),
// longcat-2.0:free free ("Requests on this model cost no credits", while it lasts).
const DEAL_LABELS: Record<string, string> = {
  "minimax-m3": "2x usage",
  "mimo-v2.5": "up to -99%",
  "mimo-v2.5-pro": "up to -99%",
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
        target.models[registrationId] ??= {
          name: label ? `${model.name ?? key} (${label})` : (model.name ?? key),
          limit: {
            context: model.context_length ?? DEFAULT_CONTEXT,
            output: DEFAULT_OUTPUT,
          },
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