# Primeiros passos

## Pré-requisitos
- **Claude Code** instalado.
- **`gh` autenticado** na sua conta do GitHub (`gh auth login`). Todas as etapas leem e escrevem issues, labels e PRs por ele.
- **Context7**, opcional mas recomendado. As skills `spec` e `implementar` consultam por ele a documentação atual das bibliotecas. Instale uma vez por máquina:
  ```
  npx ctx7 setup --claude
  ```
  - **Modo:** escolha o modo MCP.
  - **O que o comando faz:** faz login por OAuth, gera uma API key e configura o servidor em `~/.claude.json`.
  - **Onde fica a chave:** só nesse arquivo, nunca no repositório.
  - **Sem o Context7:** as skills usam a documentação local do pacote ou o conhecimento do modelo, e marcam a API como não verificada.

  O motivo de não vir dentro do plugin está no [ADR 0001](adr/0001-context7-instalado-por-usuario.md).

## Instalar o plugin
No Claude Code:
```
/plugin marketplace add ftenorio99/fabrica
/plugin install fabrica@fabrica
```

## Configurar a máquina e o repositório
Rode `/fabrica:setup` no clone de um projeto. Ele faz duas coisas:
- **Labels:** cria ou corrige as labels do fluxo no repositório. É seguro rodar de novo.
- **Hooks do git:** na primeira vez em cada máquina, pede confirmação e instala os hooks globais que recusam commit e push na `main`. Veja [Princípios](principios.md#main-protegida).

Num projeto novo, o `/fabrica:prd` já cria as labels ao terminar. Se o repositório ainda não existir no GitHub, rode `/fabrica:setup` depois do `gh repo create`.

## Atualizar o plugin
Quando a fábrica ganhar uma versão nova (um PR mergeado neste repositório):
```
/plugin marketplace update fabrica
/reload-plugins
```
Os hooks do git instalados na máquina se atualizam sozinhos na próxima sessão, quando a versão muda.

## Onde rodar cada comando
| Comando | Onde |
|---|---|
| `/fabrica:prd`, `/fabrica:backlog`, `/fabrica:triagem`, `/fabrica:spec`, `/fabrica:implementar`, `/fabrica:revisar` | No clone do repositório da issue, por exemplo `~/projetos/kairo`. Eles usam o repositório do diretório atual. |
| `/fabrica:setup` | No clone do repositório, ou de qualquer lugar passando `<dono>/<repo>`. |
| `/fabrica:status` | Em qualquer diretório. Ele olha todos os seus repositórios, ou só um, se você passar o nome. |

O `/fabrica:status` diz, para cada passo, o comando e o diretório em que rodá-lo.

## Desenvolver a própria fábrica
Para testar mudanças no plugin sem instalar: `claude --plugin-dir ~/projetos/fabrica`. Mudar a fábrica segue o mesmo fluxo de qualquer projeto: issue, spec, PR.
