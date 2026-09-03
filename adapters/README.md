# Adapters por harness (opcionales)

La metodología (`../AGENTS.md`, `../agents/`, `../workflows/`, `../skills/`,
`../scripts/`, `../normativa/`) es agnóstica: funciona con cualquier harness o modelo.
Esta carpeta contiene los perfiles concretos, úsalos **solo si usas ese harness**.
Si usas otro (codex u otro), crea `adapters/<tu-harness>/` con tus equivalencias sin
tocar la capa genérica.

| Perfil | Qué es | Origen |
|---|---|---|
| `claude/` | agentes, comandos `/opsx:*`, skills y `settings.json` para Claude Code | ex-`sistema-a/.claude/` verbatim |
| `opencode/` | agentes, comandos `/opsx-*`, skills, `opencode.json`, `opencode/chains/ui-change.md` para OpenCode | ex-`sistema-a/.opencode/` + `opencode*.json` verbatim |

Notas:
- `claude/settings.local.json` es configuración personal de máquina (rutas absolutas,
  allowlists). No lo copies tal cual: úsalo como ejemplo.
- `opencode/` excluye `node_modules/` (dependencias reinstalables, se quedan en el shim
  de `archivo/sistema-a/.opencode/node_modules/`).
- `opencode/chains/ui-change.md` requiere el plugin `opencode-chain-prompt`: solo OpenCode.
- Los dos perfiles difieren solo en cabeceras de permisos y ortografía del disparador;
  el cuerpo (roles, flujos openspec) es el mismo y su versión canónica genérica vive arriba.
- Ningún documento declara qué harness "manda": se trabaja con el que el humano indique
  por fase. Registrar la elección en el ledger de `ejecucion/`.
