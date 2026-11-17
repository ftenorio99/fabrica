// Adaptador da fábrica para o OpenCode (fase 1 do opencode/PLANO-OPENCODE.md).
// Registra as skills de skills/*/SKILL.md e um comando /fabrica:<etapa> por skill.
// O texto das skills é lido dos arquivos a cada reload e a cada execução: este
// arquivo não guarda cópia dele. Não escreve em disco nem usa a rede.
import { Plugin, Skill } from "@opencode/plugin"
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
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
  if (!existsSync(skillsDir) || !statSync(skillsDir).isDirectory()) {
    console.error(`${LOG_PREFIX} raiz sem pasta skills/: ${root}`)
    return []
  }
  const skills: SkillSource[] = []
  for (const folder of readdirSync(skillsDir).sort()) {
    const path = join(skillsDir, folder, "SKILL.md")
    try {
      if (!statSync(join(skillsDir, folder)).isDirectory() || !existsSync(path)) continue
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

function resolveRoot(options: Record<string, unknown> | undefined): string {
  const fromOptions = options?.["root"]
  if (typeof fromOptions === "string" && fromOptions.length > 0) return resolve(fromOptions)
  // Sem options.root, a raiz é a pasta pai da pasta deste arquivo.
  return resolve(dirname(fileURLToPath(import.meta.url)), "..")
}

export default Plugin.define({
  id: "fabrica",
  async setup(ctx: any) {
    let root: string
    try {
      root = resolveRoot(ctx.options)
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
            content: parseFrontmatter(readFileSync(skill.path, "utf8"))?.body ?? "",
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
              // Se o SKILL.md sumiu ou ficou ilegível, o erro volta para quem
              // executou o comando, sem derrubar o servidor.
              const text = buildText(root, skill.folder, args)
              await ctx.session.prompt({ ...prompt, sessionID, text, delivery })
            },
          })
        } catch (error) {
          console.error(`${LOG_PREFIX} comando ${skill.folder} não registrado: ${String(error)}`)
        }
      }
    })
  },
})
