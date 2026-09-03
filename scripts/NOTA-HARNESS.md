# Scripts — qué es genérico y qué está amarrado a un harness

Origen: ex-`sistema-a/bin/`, verbatim. No se reescriben en esta fase (pulir la
metodología es el siguiente paso); esta nota declara su dependencia real.

| Script | Dependencia | Estado |
|---|---|---|
| `checkpoint.sh` | ninguna (bash + python3) | genérico |
| `estado.sh` | ninguna (lee el ledger) | genérico |
| `sombra.sh` | ninguna | genérico |
| `verificar.sh` | ninguna para correr; su comentario de cabecera nombraba `metodologia/agents/verificador.md` del harness — léase `metodologia/agents/verificador.md` | genérico (cabecera pendiente de retoque menor) |
| `flota.sh` | **requiere el binario `opencode`** (`exec opencode "$@"`) | amarrado a OpenCode → solo vía `adapters/opencode/` |
| `metricas.sh` | **lee la base de OpenCode** (`~/.local/share/opencode/opencode.db`) | amarrado a OpenCode → solo vía `adapters/opencode/` |

Regla: con otro harness, `flota.sh` y `metricas.sh` no se usan; se sustituyen por el
equivalente del harness y se registra en el ledger. El contrato que sí es genérico es
el formato del ledger (`metodologia/normativa/HANDOFF.md`), no la herramienta que lo escribe.
