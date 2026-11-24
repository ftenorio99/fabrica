// Adaptador da fábrica para o OpenCode (fases 1 a 3 do opencode/PLANO-OPENCODE.md).
// Registra as skills de skills/*/SKILL.md, um comando /fabrica:<etapa> por skill,
// o subagente fabrica/revisor e os hooks de proteção, que chamam os scripts de
// hooks/. O texto das skills e do revisor é lido dos arquivos a cada reload e a
// cada execução: este arquivo não guarda cópia dele. Não escreve em disco nem
// usa a rede.
import { Plugin, Skill } from "@opencode/plugin"
import { spawnSync } from "node:child_process"
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from "node:fs"
import { homedir } from "node:os"
import { basename, dirname, isAbsolute, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

// Separador entre "fabrica" e a etapa no nome do comando. Se o TUI recusar o
// ":", troque por "/" (decisão da SPEC-157).
const COMMAND_SEPARATOR = ":"

const LOG_PREFIX = "[fabrica]"

type SkillSource = {
  folder: string
  name: string
  description: string
  argumentHint?: string
  autoinvoke: boolean
  path: string
  body: string
}

// Lê o frontmatter plano das skills: o bloco entre as duas primeiras linhas
// "---", uma "chave: valor" por linha, dividida no primeiro ":". Aspas em
// volta do valor são tiradas. Sem o bloco, devolve undefined.
export function parseFrontmatter(
  text: string,
): { fields: Record<string, string>; body: string } | undefined {
  const lines = text.replace(/\r\n/g, "\n").split("\n")
  if (lines[0]?.trim() !== "---") return undefined
  const end = lines.findIndex((line, i) => i > 0 && line.trim() === "---")
  if (end < 0) return undefined
  const fields: Record<string, string> = {}
  for (const line of lines.slice(1, end)) {
    const colon = line.indexOf(":")
    if (colon <= 0) continue
    const key = line.slice(0, colon).trim()
    let value = line.slice(colon + 1).trim()
    if (value.length >= 2 && (value[0] === '"' || value[0] === "'") && value.at(-1) === value[0]) {
      value = value.slice(1, -1)
    }
    fields[key] = value
  }
  const body = lines.slice(end + 1).join("\n").replace(/^\n+/, "")
  return { fields, body }
}

// Lista as skills válidas da raiz. Pasta sem SKILL.md é ignorada sem erro;
// SKILL.md sem frontmatter, sem name ou sem description é ignorado com erro.
export function loadSkills(root: string): SkillSource[] {
  const skillsDir = join(root, "skills")
  const skills: SkillSource[] = []
  let folders: string[]
  try {
    if (!existsSync(skillsDir) || !statSync(skillsDir).isDirectory()) {
      console.error(`${LOG_PREFIX} raiz sem pasta skills/: ${root}`)
      return []
    }
    folders = readdirSync(skillsDir).sort()
  } catch (error) {
    // Erro de permissão ou de leitura na pasta: as skills somem, mas o plugin segue.
    console.error(`${LOG_PREFIX} não foi possível ler skills/: ${String(error)}`)
    return []
  }
  for (const folder of folders) {
    const path = join(skillsDir, folder, "SKILL.md")
    try {
      if (!statSync(join(skillsDir, folder)).isDirectory() || !existsSync(path)) continue
      // Uma leitura só: metadados e corpo saem do mesmo texto.
      const parsed = parseFrontmatter(readFileSync(path, "utf8"))
      const name = parsed?.fields["name"]
      const description = parsed?.fields["description"]
      if (!parsed || !name || !description) {
        console.error(`${LOG_PREFIX} skill ignorada, frontmatter sem name ou description: ${path}`)
        continue
      }
      skills.push({
        folder,
        name,
        description,
        argumentHint: parsed.fields["argument-hint"] || undefined,
        autoinvoke: parsed.fields["disable-model-invocation"] !== "true",
        path,
        body: parsed.body,
      })
    } catch (error) {
      console.error(`${LOG_PREFIX} skill ignorada, erro ao ler ${path}: ${String(error)}`)
    }
  }
  return skills
}

// Preâmbulo da §4.3 do plano, igual para todas as etapas.
function preamble(root: string, folder: string): string {
  const base = join(root, "skills", folder)
  return [
    "<!-- fabrica:opencode -->",
    "Esta etapa da fábrica roda no OpenCode. O diretório base desta skill é",
    `${base}: resolva "<diretório base desta skill>" e os caminhos`,
    "relativos a partir dele. Adaptações desta harness, sem mudar as regras:",
    '- "AskUserQuestion" é a ferramenta `question`.',
    '- "fabrica:revisor" é o subagente `fabrica/revisor`, chamado pela ferramenta',
    "  `subagent`; se ele não estiver disponível, use o fallback que a própria",
    "  skill descreve.",
    "- Statusline, `~/.claude/settings.json` e `setup-statusline.sh` são do Claude",
    "  Code: não execute esses passos, avise que não se aplicam ao OpenCode e siga.",
    "O restante vale sem alteração.",
  ].join("\n")
}

// Monta o texto enviado à sessão: preâmbulo + corpo do SKILL.md, lido agora,
// com cada $ARGUMENTS trocado pelo argumento como texto literal.
export function buildText(root: string, folder: string, args: string): string {
  const path = join(root, "skills", folder, "SKILL.md")
  const parsed = parseFrontmatter(readFileSync(path, "utf8"))
  if (!parsed) throw new Error(`${LOG_PREFIX} SKILL.md sem frontmatter: ${path}`)
  // split/join, e não replace: o replace interpretaria $&, $1 e $$ no argumento.
  const body = parsed.body.split("$ARGUMENTS").join(args)
  return `${preamble(root, folder)}\n\n${body}`
}

// Subagente revisor (fase 2 do plano, §4.4). O prompt vem do agents/revisor.md,
// lido a cada setup e reload; este arquivo só define o modo e as permissões.
const REVIEWER_ID = "fabrica/revisor"

// A última regra que casa vence. As regras 1 a 4 repetem a base dos agentes do
// OpenCode; as seguintes deixam o revisor sem editar, perguntar ou abrir outro
// subagente. O shell continua liberado, como o Bash do revisor no Claude Code.
const REVIEWER_PERMISSIONS = [
  { action: "*", resource: "*", effect: "allow" },
  { action: "read", resource: "*.env", effect: "ask" },
  { action: "read", resource: "*.env.*", effect: "ask" },
  { action: "read", resource: "*.env.example", effect: "allow" },
  { action: "edit", resource: "*", effect: "deny" },
  { action: "question", resource: "*", effect: "deny" },
  { action: "subagent", resource: "*", effect: "deny" },
]

// Lê agents/revisor.md da raiz. Ausente, ilegível, sem frontmatter ou sem
// description: devolve undefined e loga o erro.
export function loadReviewer(
  root: string,
): { name: string; description: string; system: string } | undefined {
  const path = join(root, "agents", "revisor.md")
  try {
    if (!existsSync(path)) {
      console.error(`${LOG_PREFIX} agente revisor não registrado, arquivo ausente: ${path}`)
      return undefined
    }
    const parsed = parseFrontmatter(readFileSync(path, "utf8"))
    const description = parsed?.fields["description"]
    if (!parsed || !description) {
      console.error(`${LOG_PREFIX} agente revisor não registrado, frontmatter sem description: ${path}`)
      return undefined
    }
    return { name: parsed.fields["name"] || "revisor", description, system: parsed.body }
  } catch (error) {
    console.error(`${LOG_PREFIX} agente revisor não registrado, erro ao ler ${path}: ${String(error)}`)
    return undefined
  }
}

// Hooks de proteção (fase 3 do plano, §4.5). As regras ficam nos scripts de
// hooks/, os mesmos do Claude Code; aqui só se chama cada um com a linha inteira.
const PROTECTION_SCRIPTS = ["protect-main.sh", "protect-production.sh"]
const SCRIPT_TIMEOUT_MS = 10_000
// Limite do Map da ponte: uma chamada que nunca chega à permissão não deixa a
// memória crescer.
const PENDING_LIMIT = 256

const CLAUDE_GUARD_MESSAGE =
  `${LOG_PREFIX} No OpenCode, a fábrica não altera a configuração do Claude Code ` +
  `(~/.claude) nem a statusline. Esse passo é só do Claude Code.`

type HookResult = { deny: boolean; reason?: string }

// Chama um script de hooks/ com o JSON do Claude Code. Falha, timeout ou saída
// que não é JSON contam como "sem negativa", como nos scripts quando falta o jq.
export function runHookScript(root: string, script: string, command: string, cwd: string): HookResult {
  const path = join(root, "hooks", script)
  const result = spawnSync("bash", [path], {
    input: JSON.stringify({ tool_input: { command }, cwd }),
    encoding: "utf8",
    timeout: SCRIPT_TIMEOUT_MS,
  })
  if (result.error || result.status !== 0) {
    const why = result.error ? String(result.error) : `código ${result.status}: ${result.stderr.trim()}`
    console.error(`${LOG_PREFIX} ${script} falhou (${why}); o comando não foi negado por ele`)
    return { deny: false }
  }
  const output = result.stdout.trim()
  if (!output) return { deny: false }
  try {
    const parsed = JSON.parse(output)
    const decision = parsed?.hookSpecificOutput
    if (decision?.permissionDecision === "deny") {
      return { deny: true, reason: String(decision.permissionDecisionReason ?? "") }
    }
  } catch (error) {
    console.error(`${LOG_PREFIX} ${script} devolveu algo que não é JSON; o comando não foi negado por ele`)
  }
  return { deny: false }
}

// Caminho canônico: resolve links simbólicos do ponto mais próximo que existe,
// para que um link para ~/.claude não escape da checagem. O resto, que ainda
// não existe, é anexado como está.
export function canonicalPath(path: string): string {
  let current = resolve(path)
  const rest: string[] = []
  while (!existsSync(current)) {
    const parent = dirname(current)
    if (parent === current) break
    rest.unshift(basename(current))
    current = parent
  }
  try {
    return join(realpathSync(current), ...rest)
  } catch {
    return resolve(path)
  }
}

// Guarda-corpo do Claude Code: nega as linhas de shell que citam o ~/.claude ou
// o setup-statusline.sh e as edições dentro do ~/.claude. É uma regra de texto:
// a linha de shell não diz se escreve, então toda citação conta.
export function claudeGuard(
  action: string,
  items: string[],
  home: string,
  cwd: string = process.cwd(),
): string | undefined {
  const claudeDir = join(home, ".claude")
  if (action === "shell") {
    const markers = ["~/.claude", "$HOME/.claude", "${HOME}/.claude", claudeDir, "setup-statusline.sh"]
    return items.some((line) => markers.some((marker) => line.includes(marker)))
      ? CLAUDE_GUARD_MESSAGE
      : undefined
  }
  if (action === "edit") {
    const realClaudeDir = canonicalPath(claudeDir)
    const inside = (item: string) => {
      const path = item.startsWith("~/") ? join(home, item.slice(2)) : item
      // Caminho relativo vale a partir do diretório do projeto.
      const full = canonicalPath(isAbsolute(path) ? path : resolve(cwd, path))
      return full === realClaudeDir || full.startsWith(realClaudeDir + "/")
    }
    return items.some(inside) ? CLAUDE_GUARD_MESSAGE : undefined
  }
  return undefined
}

// Os três passos de uma linha de shell, na ordem, parando na primeira negativa.
export function evaluateShell(root: string, line: string, cwd: string, guard: boolean): HookResult {
  for (const script of PROTECTION_SCRIPTS) {
    const result = runHookScript(root, script, line, cwd)
    if (result.deny) return result
  }
  if (guard) {
    const message = claudeGuard("shell", [line], homedir())
    if (message) return { deny: true, reason: message }
  }
  return { deny: false }
}

// options.root aceita "~/..." (pasta pessoal) e caminho relativo, que vale a
// partir do diretório do projeto aberto. Sem options.root, a raiz é a pasta pai
// da pasta deste arquivo.
export function resolveRoot(options: Record<string, unknown> | undefined, baseDir: string): string {
  const fromOptions = options?.["root"]
  if (typeof fromOptions === "string" && fromOptions.length > 0) {
    const expanded = fromOptions === "~" || fromOptions.startsWith("~/")
      ? join(homedir(), fromOptions.slice(1))
      : fromOptions
    return resolve(baseDir, expanded)
  }
  return resolve(dirname(fileURLToPath(import.meta.url)), "..")
}

// Nota de sessão (§4.5 do plano): equivale ao SessionStart do Claude Code.
const HOOKS_NOTE =
  "Os hooks do git da fábrica não estão instalados nesta máquina. Rode /fabrica:setup."

// Diz se o hooksPath global do git aponta para ~/.config/fabrica/githooks.
// Qualquer falha ao ler conta como "não instalado" e é logada; nunca lança.
export function hooksInstalled(home: string = homedir()): boolean {
  // Mesmo destino do scripts/setup-githooks.sh: ${XDG_CONFIG_HOME:-$HOME/.config}.
  const xdg = process.env.XDG_CONFIG_HOME
  const configDir = xdg && isAbsolute(xdg) ? xdg : join(home, ".config")
  const expected = join(configDir, "fabrica", "githooks")
  const result = spawnSync("git", ["config", "--global", "--get", "core.hooksPath"], {
    encoding: "utf8",
    timeout: 5000,
  })
  if (result.error) {
    console.error(`${LOG_PREFIX} não foi possível ler o hooksPath do git: ${String(result.error)}`)
    return false
  }
  // Código 1 é só "chave não definida", o caso normal; outro código é erro de leitura.
  if (result.status !== 0 && result.status !== 1) {
    console.error(
      `${LOG_PREFIX} git config saiu com código ${result.status}: ${(result.stderr ?? "").trim()}`,
    )
    return false
  }
  let value = (result.stdout ?? "").trim()
  if (!value) return false
  if (value === "~" || value.startsWith("~/")) value = join(home, value.slice(1))
  return resolve(value) === expected
}

export default Plugin.define({
  id: "fabrica",
  async setup(ctx: any) {
    let root: string
    try {
      root = resolveRoot(ctx.options, ctx.location?.directory ?? process.cwd())
    } catch (error) {
      console.error(`${LOG_PREFIX} não foi possível resolver a raiz: ${String(error)}`)
      return
    }

    // Os callbacks de transform rodam de novo a cada reload, então as skills
    // são lidas dos arquivos dentro deles, e não uma vez só no setup.
    await ctx.skill.transform((editor: any) => {
      for (const skill of loadSkills(root)) {
        try {
          editor.add({
            id: Skill.ID.make(`fabrica-${skill.folder}`),
            name: Skill.Name.make(skill.name),
            description: skill.description,
            path: skill.path,
            content: skill.body,
            autoinvoke: skill.autoinvoke,
          })
        } catch (error) {
          console.error(`${LOG_PREFIX} skill ${skill.folder} não registrada: ${String(error)}`)
        }
      }
    })

    await ctx.command.transform((editor: any) => {
      for (const skill of loadSkills(root)) {
        const description = skill.argumentHint
          ? `${skill.argumentHint} ${skill.description}`
          : skill.description
        try {
          editor.add({
            name: `fabrica${COMMAND_SEPARATOR}${skill.folder}`,
            description,
            execute: async ({ sessionID, prompt, delivery }: any) => {
              const args = typeof prompt?.text === "string" ? prompt.text.trim() : ""
              let text: string
              try {
                text = buildText(root, skill.folder, args)
              } catch (error) {
                // SKILL.md apagado ou ilegível: o erro vai para a sessão como
                // mensagem sintética, sem derrubar o servidor. Se nem isso der,
                // o erro volta a quem executou o comando.
                const message = `${LOG_PREFIX} não foi possível ler a skill ${skill.folder}: ${String(error)}`
                console.error(message)
                await ctx.session.synthetic({ sessionID, text: message })
                return
              }
              await ctx.session.prompt({ ...prompt, sessionID, text, delivery })
            },
          })
        } catch (error) {
          console.error(`${LOG_PREFIX} comando ${skill.folder} não registrado: ${String(error)}`)
        }
      }
    })

    // O update de um ID novo cria o agente (plano, §4.4). Qualquer erro aqui é
    // logado e não impede o resto do plugin.
    try {
      await ctx.agent.transform((editor: any) => {
        const reviewer = loadReviewer(root)
        if (!reviewer) return
        editor.update(REVIEWER_ID, (agent: any) => {
          agent.id = REVIEWER_ID
          agent.name = reviewer.name
          agent.description = reviewer.description
          agent.system = reviewer.system
          agent.mode = "subagent"
          agent.hidden = false
          agent.permissions = REVIEWER_PERMISSIONS.map((rule) => ({ ...rule }))
        })
      })
    } catch (error) {
      console.error(`${LOG_PREFIX} agente revisor não registrado: ${String(error)}`)
    }

    // Proteção. O protectClaudeConfig: false desliga só o guarda-corpo, nunca
    // os scripts de hooks/.
    const guard = ctx.options?.["protectClaudeConfig"] !== false
    const cwd: string = ctx.location?.directory ?? process.cwd()
    for (const script of PROTECTION_SCRIPTS) {
      if (!existsSync(join(root, "hooks", script))) {
        console.error(`${LOG_PREFIX} script de proteção ausente: ${join(root, "hooks", script)}`)
      }
    }

    // Ponte pelo id da chamada: a linha inteira só chega no execute.before; o
    // permission.evaluate traz cada comando separado em resources.
    const pending = new Map<string, string>()
    try {
      await ctx.tool.hook("execute.before", (event: any) => {
        try {
          if (event?.tool !== "shell") return
          const command = event?.input?.command
          if (typeof command !== "string" || typeof event?.id !== "string") return
          pending.delete(event.id)
          pending.set(event.id, command)
          while (pending.size > PENDING_LIMIT) {
            pending.delete(pending.keys().next().value as string)
          }
        } catch (error) {
          console.error(`${LOG_PREFIX} erro no tool.execute.before: ${String(error)}`)
        }
      })
    } catch (error) {
      console.error(`${LOG_PREFIX} hook tool.execute.before não registrado: ${String(error)}`)
    }

    // A negativa fica no hook de permissão, que é o que barra a ferramenta.
    try {
      await ctx.permission.hook("evaluate", (event: any) => {
        try {
          const resources: string[] = Array.isArray(event?.resources) ? event.resources.map(String) : []
          if (event?.action === "shell") {
            const id = event?.source?.id
            const bridged = typeof id === "string" ? pending.get(id) : undefined
            if (bridged !== undefined) pending.delete(id)
            const line = bridged ?? resources.join(" && ")
            const result = evaluateShell(root, line, cwd, guard)
            if (result.deny) {
              event.effect = "deny"
              event.message = result.reason
              const origin = bridged !== undefined ? "linha da ponte" : "resources"
              console.error(`${LOG_PREFIX} shell negado (${origin}): ${line} | motivo: ${result.reason}`)
            }
          } else if (event?.action === "edit" && guard) {
            const message = claudeGuard("edit", resources, homedir(), cwd)
            if (message) {
              event.effect = "deny"
              event.message = message
              console.error(`${LOG_PREFIX} edit negado: ${resources.join(", ")}`)
            }
          }
        } catch (error) {
          console.error(`${LOG_PREFIX} erro no permission.evaluate: ${String(error)}`)
          // Numa proteção, falhar ao avaliar o shell conta como negativa. As outras
          // ações seguem sem negativa, como antes.
          if (event?.action === "shell") {
            event.effect = "deny"
            event.message = `${LOG_PREFIX} não foi possível verificar este comando; ele foi negado por segurança.`
          }
        }
      })
    } catch (error) {
      console.error(`${LOG_PREFIX} hook permission.evaluate não registrado: ${String(error)}`)
    }

    // Harness (SPEC-200): o /fabrica:avancar lê esta variável no shell e roda a
    // etapa na sessão do OpenCode, sem claude -p. Um valor já definido pelo
    // usuário é preservado; OPENCODE_SESSION_ID continua sendo a reserva.
    try {
      await ctx.shell.hook("create.before", (event: any) => {
        try {
          if (event?.env && !event.env.FABRICA_HARNESS) {
            event.env.FABRICA_HARNESS = "opencode"
          }
        } catch (error) {
          console.error(`${LOG_PREFIX} não foi possível definir FABRICA_HARNESS: ${String(error)}`)
        }
      })
    } catch (error) {
      console.error(`${LOG_PREFIX} hook shell.create.before não registrado: ${String(error)}`)
    }

    // Nota de sessão: uma vez por sessão, quando os hooks do git não estão instalados.
    const noted = new Set<string>()
    try {
      await ctx.session.hook("context", (event: any) => {
        try {
          const key = String(event?.sessionID ?? event?.session?.id ?? "default")
          if (noted.has(key)) return
          noted.add(key)
          if (hooksInstalled()) return
          event.system.push({ type: "text", text: HOOKS_NOTE })
        } catch (error) {
          console.error(`${LOG_PREFIX} erro no session.context: ${String(error)}`)
        }
      })
    } catch (error) {
      console.error(`${LOG_PREFIX} hook session.context não registrado: ${String(error)}`)
    }
  },
})
