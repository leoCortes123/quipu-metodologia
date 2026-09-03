# Workflows OpenSpec — índice genérico

Flujo spec-driven del producto. Vale con cualquier harness: la herramienta real es el
CLI `openspec`, no el comando con `/` de tu harness (la ortografía `/opsx:*` vs
`/opsx-*` vive en `metodologia/adapters/`).

| Quiero… | Workflow | Hace |
|---|---|---|
| Pensar una idea sin crear nada | `explore.md` | exploración de solo lectura |
| Crear la propuesta completa | `propose.md` | proposal + delta specs + design + tasks |
| Implementar un change aprobado | `apply.md` | ejecutar `tasks.md` con CI verde |
| Sincronizar specs tras implementar | `sync.md` | llevar el delta a `specs/` |
| Archivar un change terminado | `archive.md` | archivar change sincronizado |
| Revisar una propuesta existente | `update.md` | corregir artefactos sin cambiar intención |

Reglas duras (de `metodologia/normativa/CONSTITUCION.md` 7–8):
- Ningún change se archiva sin su delta sincronizado.
- Cada escenario cita el test que lo verifica (`openspec validate --all --strict`).
- Frontera planeación/ejecución: el workflow de planificación solo crea artefactos,
  nunca toca código de producto. La implementación espera una petición nueva.
