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
- Bash e os comandos básicos do sistema (`mktemp`, `realpath`, `od`) para o teste.

## Instalação

Não há instalador nem `package.json`. A instalação é uma entrada no `opencode.jsonc` da raiz do projeto, apontando para esta pasta:

```jsonc
// <projeto>/opencode.jsonc
{
  "plugins": ["/home/<usuário>/projetos/fabrica/opencode"]
}
```

- O caminho é uma **pasta** (a que tem o `server.ts`), não o arquivo. Caminho de arquivo é ignorado.
- A entrada fica no **projeto**: a configuração global carrega as skills e o revisor, mas não registra os comandos nem o hook de produção no projeto (veja [Limites conhecidos](#limites-conhecidos)).
- Se o `opencode.jsonc` do projeto já existe, acrescente a pasta à lista de `"plugins"` que estiver lá.
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

Ele sobe um `opencode serve` local, sem modelo, num projeto temporário com o plugin carregado pelo `opencode.jsonc` do projeto, e confere pela API:

- o plugin `fabrica` ativo, vindo desta raiz;
- os 12 comandos e as 12 skills, com o `autoinvoke` certo;
- o subagente `fabrica/revisor`;
- as decisões de permissão: commit com `--no-verify` e padrão de produção negados, escrita no `~/.claude` negada, `git status` liberado e a linha encadeada negada;
- nenhum erro do plugin na saída do servidor e no log do OpenCode, desde o começo do servidor.

Imprime `ok <verificação>` ou `falha <verificação>: <motivo>`, uma por linha, e sai com 1 se alguma falhar. `--root <pasta>` aponta para outra cópia da fábrica (útil para provar que o teste falha com um hook desligado). A VM de teste não deve ter o adaptador na configuração global: o teste usa o projeto temporário e falha se achar mais de um plugin `fabrica`.

## Rollback

1. Tire a pasta da lista `"plugins"` do `opencode.jsonc` do projeto (e da global, se você a usou).
2. Rode `opencode reload` (ou `opencode service restart`).
3. Opcionalmente, apague a pasta `opencode/` do clone. O adaptador não gera arquivo de agente nem nada em `~/.config/opencode/agents/`.

Nada em `~/.claude/` é tocado em nenhum dos dois sentidos.

## Limites conhecidos

- **A entrada global não registra os comandos nem o hook de produção no projeto:** com `"plugins"` em `~/.config/opencode/opencode.jsonc`, as 12 skills e o `fabrica/revisor` carregam em todos os projetos, mas `GET /api/command` com a localização do projeto não lista os `/fabrica:*`, e o `protect-production.sh` roda com o `cwd` global, sem achar o `.fabrica/producao.txt` do projeto (OpenCode 2.3.0). Instale pelo `opencode.jsonc` do projeto.
- **O shell digitado pelo usuário não passa pelo hook de permissão.** O hook protege o agente, não você: o comando digitado no TUI (ou em `opencode run`) só passa pelo `shell.create.before`, como no Claude Code.
- **Uma regra `deny` sua é final:** ela é aplicada antes e o hook do plugin não é chamado.
- **`opencode run "/fabrica:<etapa>"` não executa o comando.** O `run` trata o texto como mensagem comum. Para uma etapa, use o TUI ou `POST /api/session/<id>/command`.
- **A statusline não existe** no OpenCode; ela não foi portada.
- **O custo sai como `tokens=nao-medido`:** o `stage-usage.py` lê o log do Claude Code, não o do OpenCode.
- **Janela de inicialização:** logo depois de subir o servidor, alguma avaliação de permissão pode passar antes de o plugin carregar. Numa sessão com modelo, a chamada dura mais que a janela; o teste espera a sonda de negação antes de conferir.
- **O guarda-corpo do `~/.claude` é por texto:** ele nega as linhas de shell que citam o caminho ou o `setup-statusline.sh` e as edições dentro do `~/.claude`. Um script que escreve lá dentro sem citar o caminho passa. O formato do `edit` com uma ferramenta real não foi conferido.
- **O nome com `:`** foi aceito pela API. Se o TUI recusar o nome digitado, troque o separador para `/` na constante `COMMAND_SEPARATOR` do `server.ts`.
