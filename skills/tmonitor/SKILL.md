---
name: tmonitor
description: Cria e gerencia sessões tmux de monitoramento usando o TMonitor (tmonitor.sh) — N panes de comando com labels e layout, mais um shell interativo. Use SEMPRE que o usuário pedir para monitorar logs, serviços, workers, filas, builds ou deploys no terminal; subir/abrir painéis ou panes de acompanhamento; rodar vários comandos lado a lado; criar um "dashboard de terminal"; ou mencionar "tmonitor", "sessão tmux", "panes de monitoramento", "acompanhar em tempo real". Também use para recuperar sessões após reboot (--restore) ou recarregar comandos de uma sessão viva.
---

# TMonitor — sessões tmux de monitoramento para agentes

O TMonitor cria uma sessão tmux com N panes de comando (cada um rodando um comando de longa duração:
tail de log, worker, build watcher) e um shell interativo fixo no rodapé. Você monta a sessão inteira
por flags de CLI — nenhum arquivo de configuração é necessário — e entrega ao usuário uma sessão
pronta para attach.

## Localizar o script

Resolva o caminho nesta ordem e guarde numa variável:

1. `~/.tmux/scripts/tmonitor.sh` (instalação padrão)
2. `<dir desta skill>/../../tmonitor.sh` (quando a skill roda de dentro do clone do repositório)

Se nenhum existir, informe o usuário e pare — não tente reimplementar o comportamento com tmux cru;
o script cuida de layout, labels, snapshot e bindings de uma vez.

`reload_tmonitor.sh` e `tmonitor_stats.sh` moram no mesmo diretório do `tmonitor.sh`.

## Regra de ouro: sempre `--detach`

Sem `--detach`, o script termina com `tmux attach` e **bloqueia para sempre** — num contexto
não-interativo (você) isso trava o processo. Crie a sessão detached e entregue ao usuário o comando
de attach. Não existe caso em que um agente deva omitir `--detach`.

## Criar uma sessão ad-hoc (sem arquivo de configuração)

```bash
"$TMONITOR" --session="deploy-watch" \
  --pane-1="kubectl get pods -w" --label-1="pods" \
  --pane-2="stern api" --label-2="api logs" \
  --pane-3="watch -n5 kubectl top nodes" --label-3="nodes" \
  --detach
```

Diretrizes de montagem:

- **`--session`**: nome curto e descritivo do que está sendo monitorado (`deploy-watch`,
  `laravel-dev`). Não pode conter `:` nem `.`, e evite deixar o default `monitoring` — sessões com o
  mesmo nome colidem entre projetos (inclusive o snapshot de recuperação).
- **`--pane-N`**: índices sequenciais a partir de 1, sem buracos (`--pane-1`, `--pane-3` é erro).
  Prefira comandos que permanecem vivos (tail -f, watch, workers); um comando que termina deixa o
  pane num shell comum.
- **`--label-N`**: sempre rotule — o label aparece na borda do pane e é como o usuário se orienta.
- **`--layout`**: `columns` (default) serve até ~3 panes; `grid` para 4 ou mais; `rows` quando as
  saídas têm linhas longas (logs) que sofrem em colunas estreitas.
- **Workdir**: primeiro argumento posicional. Passe o diretório do projeto quando os comandos
  dependem dele (ex.: `php artisan ...`); se omitido, vale o diretório corrente.

## Usar o tmonitor.conf de um projeto

Se o diretório do projeto tem um `tmonitor.conf` (variáveis `CMD1..CMDN`, `LABEL1..N`, `LAYOUT`,
`SESSION_NAME`), basta:

```bash
"$TMONITOR" /caminho/do/projeto --detach
```

Flags de CLI sobrescrevem o conf **chave a chave** — útil para trocar um único pane numa sessão que
no resto segue o conf do projeto:

```bash
"$TMONITOR" /caminho/do/projeto --pane-2="php artisan queue:work --queue=urgent" --detach
```

## Depois de criar: verificar e entregar

1. Confirme que deu certo (exit code 0 e a sessão existe):

   ```bash
   tmux has-session -t "=deploy-watch" && tmux list-panes -t "=deploy-watch:0" -F '#{pane_title}'
   ```

2. Você pode ler a saída de um pane para checar se os comandos subiram de verdade (pane N-1 = CMDN;
   o shell é o último):

   ```bash
   tmux capture-pane -p -t "=deploy-watch:0.0" | tail -20
   ```

3. Entregue ao usuário o comando de attach e os atalhos:
   - `tmux attach -t deploy-watch` (se o usuário já estiver dentro do tmux:
     `tmux switch-client -t deploy-watch`)
   - Dentro da sessão: `Opt+R` recarrega os comandos, `Opt+Q` encerra com confirmação.

## Gerenciar sessões existentes

- **Sessão com o mesmo nome já existe**: o script **não** recria — apenas avisa (com `--detach`) ou
  faz attach. Para descartar e recriar use `--force`, mas isso **mata processos em execução**:
  confirme com o usuário antes, a menos que ele já tenha pedido explicitamente para recriar.
- **Recarregar comandos** (após editar o conf, ou para reiniciar os processos dos panes):

  ```bash
  "$(dirname "$TMONITOR")/reload_tmonitor.sh" deploy-watch
  ```

  O reload reenvia os comandos aos panes existentes sem mexer na geometria. Se o número de comandos
  mudou, é caso de `--force` (recriar).
- **Recuperar após reboot/kill-server**: cada sessão grava um snapshot em
  `~/.tmux/tmonitor/state/`. `"$TMONITOR" --restore` lista os disponíveis;
  `"$TMONITOR" --restore deploy-watch --detach` recria a sessão (re-executa os comandos; não
  restaura o scrollback antigo).
- **Encerrar**: `tmux kill-session -t "=deploy-watch"`.

## Exemplos de tradução pedido -> comando

**"acompanha os logs e a fila do meu projeto Laravel enquanto eu desenvolvo"** (em `~/app`):

```bash
"$TMONITOR" ~/app --session="laravel-dev" \
  --pane-1="tail -f storage/logs/laravel.log" --label-1="logs" \
  --pane-2="php artisan queue:work" --label-2="queue" \
  --pane-3="npm run dev" --label-3="vite" \
  --detach
```

**"quero ver de perto esse deploy no k8s, uns 4 pontos de vista"**:

```bash
"$TMONITOR" --session="k8s-deploy" --layout=grid \
  --pane-1="kubectl get pods -w -n prod" --label-1="pods" \
  --pane-2="kubectl get events -w -n prod" --label-2="events" \
  --pane-3="stern -n prod api" --label-3="api logs" \
  --pane-4="watch -n10 kubectl top pods -n prod" --label-4="recursos" \
  --detach
```

**"meu mac reiniciou, recupera aquela sessão de ontem"**:

```bash
"$TMONITOR" --restore            # listar o que existe
"$TMONITOR" --restore k8s-deploy --detach
```
