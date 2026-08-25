import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

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

const DEAL_LABELS: Record<string, string> = {
  "gemini-3.7-flash": "-50%",
  "minimax-m3": "2x usage",
  "mimo-v2.5": "up to 99% off",
  "mimo-v2.5-pro": "up to 99% off",
  "ox-alpha": "free",
  "laguna-s-2.1-free": "free",
}

const isClaude = (id: string) => /^claude/i.test(id)
const isSnapshot = (id: string) => /-\d{8}$/.test(id)

function dealLabel(id: string): string | undefined {
  const base = (id.split("/").pop() ?? id).toLowerCase()
  return DEAL_LABELS[base]
}

function authFilePath(): string {
  const xdg = process.env.XDG_DATA_HOME
  if (xdg) {
    const candidate = join(xdg, "opencode", "auth.json")
    if (existsSync(candidate)) return candidate
  }
  return join(homedir(), ".local", "share", "opencode", "auth.json")
}

function readStoredApiKey(): string | undefined {
  try {
    const raw = JSON.parse(readFileSync(authFilePath(), "utf8")) as Record<
      string,
      { type?: string; key?: string }
    >
    return raw[PROVIDER_ID]?.key ?? raw[ANTHROPIC_PROVIDER_ID]?.key
  } catch {
    return undefined
  }
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

async function probeAccess(models: CommandCodeModel[], log: Logger): Promise<void> {
  const key = readStoredApiKey()
  if (!key) return

  const candidates = models.filter((m) => !isClaude(m.id))
  const model =
    candidates.find((m) => m.id === "gpt-5.4-mini")?.id ?? candidates[0]?.id
  if (!model) return

  try {
    const response = await fetch(`${BASE_URL}/chat/completions`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${key}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: "." }],
        max_tokens: 1,
      }),
    })

    if (response.status === 401) {
      await log("error", "stored API key rejected (401) - run /connect again")
    } else if (response.status === 403) {
      await log(
        "error",
        "your CommandCode plan has no API access (403 upgrade_required) - upgrade at commandcode.ai",
      )
    } else if (response.status === 422) {
      await log("warn", "ZDR requested but no ZDR-capable upstream exists (422)")
    }
  } catch {
    // network errors here are non-fatal; real requests will surface them
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

        const target = isClaude(model.id) ? anthropic : openai
        const label = dealLabel(model.id)

        target.models ??= {}
        target.models[model.id] ??= {
          name: label ? `${model.name ?? model.id} (${label})` : (model.name ?? model.id),
          limit: {
            context: model.context_length ?? DEFAULT_CONTEXT,
            output: DEFAULT_OUTPUT,
          },
        }
        registered++
      }

      await log("info", `registered ${registered} models`)
      await probeAccess(discovered, log)
    },

    "chat.headers": async (_input, output) => {
      if (process.env.CMD_ZDR === "1") {
        output.headers["x-cmd-zdr"] = "1"
      }
    },
  }
}) satisfies Plugin

export default CommandCodeModels
