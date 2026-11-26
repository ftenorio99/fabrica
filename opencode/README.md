# Adaptador da fábrica para o OpenCode

O `opencode/server.ts` leva ao OpenCode o que o plugin do Claude Code faz: as 13 skills, um comando `/fabrica:<etapa>` por skill, o subagente `fabrica/revisor` e os hooks de proteção da main, de produção e do `~/.claude`. O texto das skills e do revisor vem dos arquivos do repositório, lidos a cada reload; o adaptador não guarda cópia.

O plugin do Claude Code não muda: esta pasta é inerte para ele e nada em `~/.claude/` é criado ou alterado pela instalação.

| Recurso | No OpenCode |
|---|---|
| Skills | as 13, com ID `fabrica-<pasta>`; `autoinvoke: false` nas 11 com `disable-model-invocation: true` |
| Comandos | os 13 `/fabrica:<etapa>`, com o argumento no lugar de `$ARGUMENTS` |
| Revisor | `fabrica/revisor`, subagente com o prompt do `agents/revisor.md`; não edita arquivos |
| Proteções | `hooks/protect-main.sh`, `hooks/protect-production.sh` e o guarda-corpo do `~/.claude` e da statusline, com as mesmas mensagens |
| Statusline | não existe no OpenCode; não foi portada |
| Custo | `scripts/stage-usage.py` não lê o log do OpenCode: a linha sai com `tokens=nao-medido` |
| Harness | `server.ts` injeta `FABRICA_HARNESS=opencode` no ambiente dos comandos de shell; o `/fabrica:avancar` detecta a harness e roda as etapas na sessão, sem `claude -p`, sem label `modelo:*` e sem escalonamento. `OPENCODE_SESSION_ID` é a reserva |

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

Vale em todos os projetos: as 13 skills, os 13 comandos `/fabrica:*`, o `fabrica/revisor` e os hooks de proteção, avaliados com o diretório de cada projeto. Com ela, o `protect-production.sh` lê o `.fabrica/producao.txt` do projeto da sessão.

As duas entradas podem conviver: o OpenCode mantém um plugin `fabrica`, sem duplicar os comandos nem as negações.

- O caminho é uma **pasta** (a que tem o `server.ts`), não o arquivo. Caminho de arquivo é ignorado.
- Se o `opencode.jsonc` já existe, acrescente a pasta à lista de `"plugins"` que estiver lá.
- Recarregue com `opencode reload` (ou `/reload` no TUI). Se o plugin não aparecer, reinicie o serviço com `opencode service restart` e abra o projeto de novo.
- Para conferir, abra o TUI do OpenCode **na pasta do projeto** e digite `/fabrica:`; os 13 comandos aparecem. Pela API, `GET /api/plugin` com `location[directory]=<projeto>` mostra o `fabrica` com `state.status: "active"`.
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
- os 13 comandos e as 13 skills, com o `autoinvoke` certo;
- o subagente `fabrica/revisor`;
- as decisões de permissão: commit com `--no-verify` e padrão de produção negados no projeto A, `curl https://prod.exemplo.com` liberado no projeto B, escrita no `~/.claude` negada, `git status` liberado e a linha encadeada negada;
- a janela de inicialização fechada pelo pré-carregamento (`aquecido: sem janela`): num servidor novo, depois de `GET /api/command` listar os 13 comandos, 8 avaliações seguidas de `curl https://prod.exemplo.com` saem `deny`;
- o motivo do `permissão: commit`: a API devolve só o `deny`, então o teste lê a linha `shell negado` do servidor e só dá `ok` se o motivo for a recusa de `--no-verify`, e não "hooks do git não instalados". Para isso o servidor roda com um `git config --global` próprio, com o `core.hooksPath` apontando para a pasta de hooks que o `protect-main.sh` espera no ambiente isolado; um `~/.gitconfig` da VM não interfere;
- uma linha de negação por comando negado no modo `ambos`;
- nenhum erro do plugin na saída do servidor e no log do OpenCode, desde o começo do servidor.

A configuração global do OpenCode é isolada por `XDG_CONFIG_HOME` e `XDG_DATA_HOME` numa pasta temporária, definidas só no ambiente do servidor e do cliente da API (nunca no resto do script). Se a versão instalada não respeitar as variáveis, o teste copia o `opencode.jsonc` global existente e o restaura no `trap`, no sucesso e na falha (inclusive em `INT` e `TERM`). Em nenhum caso ele deixa a entrada do plugin na configuração global, e o `ok config global intacta` confere isso.

Imprime `ok <verificação>` ou `falha <verificação>: <motivo>`, uma por linha, e sai com 1 se alguma falhar. `--root <pasta>` aponta para outra cópia da fábrica: é assim que se prova que o teste falha, com uma cópia sem o registro de comandos (`falha global: 13 comandos`) e outra com o `cwd` do `setup` no diretório pessoal (`falha global: produção do projeto`), e outra sem a linha da recusa de `--no-verify` no `hooks/protect-main.sh` (`falha projeto: permissão: commit`, porque nada mais nega o commit com o git global isolado). Na VM, a configuração global do OpenCode deve ficar sem o adaptador: o teste isola a configuração global que o servidor lê, então a instalação global da VM não interfere, e o modo `projeto` confere exatamente um plugin `fabrica`, vindo do projeto.

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
- **Edit e Write na configuração do git passam:** o adaptador leva ao `protect-main.sh` só os comandos de shell. A recusa de Edit e Write no `.git/config`, no `~/.gitconfig` e na pasta dos hooks (SPEC-204) vale só no Claude Code.
- **O custo sai como `tokens=nao-medido`:** o `stage-usage.py` lê o log do Claude Code, não o do OpenCode.
- **Janela de inicialização:** o plugin carrega por localização e de forma preguiçosa, no primeiro acesso que precisa dele (não no boot do servidor nem na criação da sessão), e leva cerca de 0,7 a 1,0 s. Nesse intervalo, as primeiras avaliações de permissão da localização passam sem os hooks do plugin. Medido com `curl https://prod.exemplo.com` repetido em sequência: a 1ª avaliação sai `deny` do próprio OpenCode, 1 a 3 seguintes saem `allow`, e o 1º `deny` do plugin chega entre 0,68 e 1,03 s (10 execuções por projeto, 3 só global, 2 com as duas entradas). Vale nas **duas instalações**, e o plugin não consegue fechá-la: os `allow` acontecem antes de o `setup` rodar, então não há código do plugin para negar antes disso. A mesma janela aparece quando o servidor passa a atender outra localização: a primeira avaliação pode cair na instância anterior do plugin (medido: sessão do projeto B, sem `.fabrica/producao.txt`, negada com o arquivo do projeto A, e `allow` na avaliação seguinte). O teste espera a sonda de negação e repete a conferência de B até o efeito esperado. O que a #176 mediu sobre como fechá-la, no OpenCode 2.3.0:

  | Caminho | Resultado | Fecha a janela? |
  |---|---|---|
  | Regra estática em `permissions` no topo do `opencode.jsonc` (`{ "action": "shell", "resource": "*prod.exemplo.com*", "effect": "deny" }`, também com `"action": "*"` e com `"curl *prod.exemplo.com*"`) | o `opencode debug config` lista a regra, mas ela **nunca negou**: `allow` nas 8 avaliações, também depois de carregar (a regra padrão `* * allow` vem depois) | não |
  | Regra estática em `agents.build.permissions`, no projeto | nega, mas só a partir de 0,73 s; as 3 primeiras avaliações (0 a 0,6 s) saíram `allow`, porque a config também é carregada por localização | não |
  | A mesma regra em `agents.build.permissions` da config global | nega a partir de 0,76 s; 1ª `deny` do OpenCode e 3 `allow` antes | não |
  | Pré-carregar a localização pelo cliente (`GET /api/command` até os 13 `fabrica:*`, ou `GET /api/agent` e 2 s) antes da sessão | as 8 avaliações seguintes saíram `deny`, desde a 1ª (1 a 2 ms) | **sim**, se o cliente faz isso antes da 1ª ferramenta |
  | Sessão com modelo | **não medido**: a VM não tem provedor, e um `opencode run` sem provedor não terminou em 120 s | desconhecido |

  Nenhuma regra estática fecha a janela, porque a config é carregada junto com a localização; só o pré-carregamento fecha, e ele é do **cliente**, não do plugin. O TUI e o `opencode run` não foram observados nesse ponto: se já pré-carregam antes da primeira ferramenta do modelo, a janela não alcança o agente. Veja "Fechar a janela" e "Medir com modelo".
- **O guarda-corpo do `~/.claude` é por texto:** ele nega as linhas de shell que citam o caminho ou o `setup-statusline.sh` e as edições dentro do `~/.claude`. Um script que escreve lá dentro sem citar o caminho passa. O formato do `edit` com uma ferramenta real não foi conferido.
- **O nome com `:`** foi aceito pela API. Se o TUI recusar o nome digitado, troque o separador para `/` na constante `COMMAND_SEPARATOR` do `server.ts`.

## Fechar a janela

O que fecha a janela de inicialização é **pré-carregar a localização** antes da primeira etapa de agente, e isso é do cliente (TUI, `opencode run`, quem chama a API), não do plugin:

1. Chame `GET /api/command` com `location[directory]=<projeto>`.
2. Espere a resposta listar os 13 comandos `fabrica:*`. Esse é o sinal de "pronto": a localização carregou com o plugin. Outro sinal é `GET /api/plugin` mostrar o `fabrica` com `state.status: "active"`.
3. Só então abra a sessão e deixe o agente rodar.

Depois disso, nenhuma avaliação de permissão passa sem o hook: o teste de aceite prova com `ok <modo>: aquecido: sem janela`, que pré-carrega num servidor e numa localização novos e avalia `curl https://prod.exemplo.com` 8 vezes seguidas, todas `deny`, nos três modos de instalação.

**Regra estática não substitui isso.** O formato que funciona é `agents.<agente>.permissions` (no projeto ou na config global), e só vale depois de a config da localização carregar, ou seja, com a mesma janela. A forma `permissions` no topo do `opencode.jsonc`, que a documentação mostra, não negou nada na 2.3.0. Uma regra a mais também seria uma segunda lista para manter ao lado do `.fabrica/producao.txt`.

## Medir com modelo

Falta saber se o TUI e o `opencode run` já pré-carregam a localização antes da primeira ferramenta do modelo. A VM do `sbx` não tem provedor, então a medição é sua, numa máquina com provedor configurado:

1. Instale o adaptador no projeto (veja "Instalação") e crie o `.fabrica/producao.txt` com `host prod.exemplo.com`.
2. Suba `opencode serve` na pasta do projeto, guardando a saída num arquivo (`opencode serve --hostname 127.0.0.1 --port 0 > servidor.out 2>&1`), com o projeto ainda **sem** ter sido aberto por outro cliente.
3. Abra uma sessão nessa localização e mande o prompt: `rode curl https://prod.exemplo.com e mostre a saída`. **Não** pré-carregue antes.
4. Confira no `servidor.out`: uma linha `[fabrica] shell negado (...)` para esse comando mostra que o hook pegou a primeira ferramenta; se o `curl` executou sem a linha, a janela alcançou o agente.
5. Registre o resultado na issue #176.

Se a janela alcançar o agente, a correção é de outro lugar (o OpenCode ou o fluxo de uso) e vira outra issue.
