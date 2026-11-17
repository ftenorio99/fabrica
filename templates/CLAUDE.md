@AGENTS.md

## Claude Code
As regras do projeto estão no `AGENTS.md`, importado acima. Este arquivo guarda só o que é do Claude Code.
- O fluxo roda pelo plugin `fabrica` (`/plugin marketplace add ftenorio99/fabrica`), com os comandos `/fabrica:*` (ex.: `/fabrica:status`, `/fabrica:avancar`).
- Os hooks do plugin valem neste projeto: o `protect-main` impede desligar os hooks do git, e o `protect-production` recusa comandos que citem os hosts e os literais de `.fabrica/producao.txt`.
