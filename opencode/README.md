# Adaptador da fábrica para o OpenCode

O `opencode/server.ts` leva ao OpenCode o que o plugin do Claude Code faz: as 12 skills, um comando `/fabrica:<etapa>` por skill, o subagente `fabrica/revisor` e os hooks de proteção da main, de produção e do `~/.claude`. O texto das skills e do revisor vem dos arquivos do repositório, lidos a cada reload; o adaptador não guarda cópia.

O plugin do Claude Code não muda: esta pasta é inerte para ele e nada em `~/.claude/` é criado ou alterado pela instalação.

| Recurso | No OpenCode |
|---|---|
| Skills | as 12, com ID `fabrica-<pasta>`; `autoinvoke: false` nas 10 com `disable-model-invocation: true` |
| Comandos | os 12 `/fabrica:<etapa>`, com o argumento no lugar de `$ARGUMENTS` |
| Revisor | `fabrica/revisor`, subagente com o prompt do `agents/revisor.md`; não edita arquivos |
| Proteções | `hooks/protect-main.sh`, `hooks/protect-production.sh` e o guarda-corpo do `~/.claude` e da statusline, com as mesmas mensagens |
| Statusline | não existe no OpenCode; não foi portada |
| Custo | `scripts/stage-usage.py` não lê o log do OpenCode: a linha sai com `tokens=nao-medido` |

## Requisitos

- OpenCode 2.3.0, com a API de plugins v2. Ela é nova e pode mudar; o teste de aceite acusa a quebra.
- `git` e `jq`: os dois hooks de `hooks/` usam os dois. Sem o `jq`, as proteções saem sem decidir e deixam passar, como no Claude Code.
- Bash e os comandos básicos do sistema (`mktemp`, `realpath`, `od`, `sha256sum`) para o teste.

## Instalação

Não há instalador nem `package.json`. A instalação é uma entrada no `opencode.jsonc`, apontando para esta pasta. Ela pode ficar no projeto ou na configuração global do OpenCode.

**Por projeto** (`<projeto>/opencode.jsonc`):

```jsonc
// <projeto>/opencode.jsonc
{
  "plugins": ["/home/<usuário>/projetos/fabrica/opencode"]
}
```

Vale só no projeto. É a opção quando a fábrica deve existir apenas nos projetos escolhidos.

**Global** (`~/.config/opencode/opencode.jsonc`):

```jsonc
// ~/.config/opencode/opencode.jsonc
{
  "plugins": ["/home/<usuário>/projetos/fabrica/opencode"]
}
```

Vale em todos os projetos: as 12 skills, os 12 comandos `/fabrica:*`, o `fabrica/revisor` e os hooks de proteção, avaliados com o diretório de cada projeto. Com ela, o `protect-production.sh` lê o `.fabrica/producao.txt` do projeto da sessão.

As duas entradas podem conviver: o OpenCode mantém um plugin `fabrica`, sem duplicar os comandos nem as negações.

- O caminho é uma **pasta** (a que tem o `server.ts`), não o arquivo. Caminho de arquivo é ignorado.
- Se o `opencode.jsonc` já existe, acrescente a pasta à lista de `"plugins"` que estiver lá.
- Recarregue com `opencode reload` (ou `/reload` no TUI). Se o plugin não aparecer, reinicie o serviço com `opencode service restart` e abra o projeto de novo.
- Para conferir, abra o TUI do OpenCode **na pasta do projeto** e digite `/fabrica:`; os 12 comandos aparecem. Pela API, `GET /api/plugin` com `location[directory]=<projeto>` mostra o `fabrica` com `state.status: "active"`.
- Projetos com `AGENTS.md` recebem as regras sozinhos. Num projeto só com `CLAUDE.md`, acrescente `"instructions": ["CLAUDE.md"]` ao mesmo `opencode.jsonc` do projeto.

## Atualização

`git pull` no clone e `opencode reload` (ou `opencode service restart`). O adaptador lê os `SKILL.md` e o `agents/revisor.md` a cada execução e a cada reload: não há cópia para sincronizar.

## Teste

O teste de aceite roda dentro de uma VM do `sbx` criada com o agente `opencode`, porque o servidor grava em `~/.config/opencode` e `~/.local/share/opencode` da máquina. No host, ele recusa rodar.

```bash
# no host, na pasta do clone: o caminho do clone no fim monta o workspace da VM
# (sem ele, o `sbx create` mostra `Workspace: none` e a VM fica sem os arquivos)
sbx create --name opencode-<projeto> opencode /caminho/do/clone

# no host, na branch que quer testar: roda o teste dentro da VM
sbx exec opencode-<projeto> bash opencode/test-adapter.sh
```

O `sbx run` abre o TUI do agente, não um shell: para o teste, use o `sbx exec`. O `sbx exec` inicia a VM se ela estiver parada, e a VM enxerga a branch que está no clone do host.

O `--install` escolhe a instalação: `projeto`, `global`, `ambos` (a entrada global e a do projeto juntas) ou `todos`, o padrão. Cada modo roda uma vez, com servidor e projetos temporários próprios: o projeto A tem `.fabrica/producao.txt` com `host prod.exemplo.com`, e o projeto B não tem o arquivo. Um valor desconhecido ou ausente no `--install` sai com 1 e mostra o uso.

Ele sobe um `opencode serve` local, sem modelo, e confere pela API, em cada modo:

- o plugin `fabrica` ativo, vindo desta raiz, com um único plugin mesmo com as duas entradas;
- os 12 comandos e as 12 skills, com o `autoinvoke` certo;
- o subagente `fabrica/revisor`;
- as decisões de permissão: commit com `--no-verify` e padrão de produção negados no projeto A, `curl https://prod.exemplo.com` liberado no projeto B, escrita no `~/.claude` negada, `git status` liberado e a linha encadeada negada;
- uma linha de negação por comando negado no modo `ambos`;
- nenhum erro do plugin na saída do servidor e no log do OpenCode, desde o começo do servidor.

A configuração global do OpenCode é isolada por `XDG_CONFIG_HOME` e `XDG_DATA_HOME` numa pasta temporária, definidas só no ambiente do servidor e do cliente da API (nunca no resto do script). Se a versão instalada não respeitar as variáveis, o teste copia o `opencode.jsonc` global existente e o restaura no `trap`, no sucesso e na falha (inclusive em `INT` e `TERM`). Em nenhum caso ele deixa a entrada do plugin na configuração global, e o `ok config global intacta` confere isso.

Imprime `ok <verificação>` ou `falha <verificação>: <motivo>`, uma por linha, e sai com 1 se alguma falhar. `--root <pasta>` aponta para outra cópia da fábrica: é assim que se prova que o teste falha, com uma cópia sem o registro de comandos (`falha global: 12 comandos`) e outra com o `cwd` do `setup` no diretório pessoal (`falha global: produção do projeto`). Na VM, a configuração global do OpenCode deve ficar sem o adaptador: o teste isola a configuração global que o servidor lê, então a instalação global da VM não interfere, e o modo `projeto` confere exatamente um plugin `fabrica`, vindo do projeto.

## Rollback

1. Tire a pasta da lista `"plugins"` do `opencode.jsonc` do projeto (e da global, se você a usou).
2. Rode `opencode reload` (ou `opencode service restart`).
3. Opcionalmente, apague a pasta `opencode/` do clone. O adaptador não gera arquivo de agente nem nada em `~/.config/opencode/agents/`.

Nada em `~/.claude/` é tocado em nenhum dos dois sentidos.

## Limites conhecidos

- **O shell digitado pelo usuário não passa pelo hook de permissão.** O hook protege o agente, não você: o comando digitado no TUI (ou em `opencode run`) só passa pelo `shell.create.before`, como no Claude Code.
- **Uma regra `deny` sua é final:** ela é aplicada antes e o hook do plugin não é chamado.
- **`opencode run "/fabrica:<etapa>"` não executa o comando.** O `run` trata o texto como mensagem comum. Para uma etapa, use o TUI ou `POST /api/session/<id>/command`.
- **A statusline não existe** no OpenCode; ela não foi portada.
- **O custo sai como `tokens=nao-medido`:** o `stage-usage.py` lê o log do Claude Code, não o do OpenCode.
- **Janela de inicialização:** o plugin carrega por localização e de forma preguiçosa, no primeiro acesso que precisa dele (não no boot do servidor nem na criação da sessão), e leva cerca de 0,7 a 1,0 s. Nesse intervalo, as primeiras avaliações de permissão da localização passam sem os hooks do plugin. Medido com `curl https://prod.exemplo.com` repetido em sequência: a 1ª avaliação sai `deny` do próprio OpenCode, 1 a 3 seguintes saem `allow`, e o 1º `deny` do plugin chega entre 0,68 e 1,03 s (10 execuções por projeto, 3 só global, 2 com as duas entradas). Vale nas **duas instalações**, e o plugin não consegue fechá-la: os `allow` acontecem antes de o `setup` rodar, então não há código do plugin para negar antes disso. A mesma janela aparece quando o servidor passa a atender outra localização: a primeira avaliação pode cair na instância anterior do plugin (medido: sessão do projeto B, sem `.fabrica/producao.txt`, negada com o arquivo do projeto A, e `allow` na avaliação seguinte). O teste espera a sonda de negação e repete a conferência de B até o efeito esperado. **Não medido:** uma sessão com modelo, que a VM sem provedor não exercita; fechar a janela está na issue separada "OpenCode: os primeiros comandos de shell de uma localização passam sem o hook de produção".
- **O guarda-corpo do `~/.claude` é por texto:** ele nega as linhas de shell que citam o caminho ou o `setup-statusline.sh` e as edições dentro do `~/.claude`. Um script que escreve lá dentro sem citar o caminho passa. O formato do `edit` com uma ferramenta real não foi conferido.
- **O nome com `:`** foi aceito pela API. Se o TUI recusar o nome digitado, troque o separador para `/` na constante `COMMAND_SEPARATOR` do `server.ts`.
