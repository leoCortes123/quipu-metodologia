# metodologia — cómo se desarrolla Quipu

Repositorio del **método de trabajo**: el contrato que gobierna a los agentes que
construyen Quipu Enterprise. Estable, agnóstico al harness, y separado a propósito del
producto, del plan y de la ejecución.

**Entrada para agentes:** `AGENTS.md`. **Entrada para el orquestador:** `SESION-EJECUCION.md`.

## Lo que esto NO es

No es el diseño de Quipu. Quipu es una herramienta para dirigir desarrollo con agentes;
esta metodología es cómo se construye esa herramienta. Se parecen —las dos hablan de
roles, evidencia y gates— y por eso conviene decirlo explícito:

| | `metodologia/` (aquí) | `conocimiento/` (el otro repo) |
|---|---|---|
| Pregunta que responde | ¿cómo trabajamos hoy para construir Quipu? | ¿qué debe llegar a ser Quipu? |
| Naturaleza | contrato vinculante | investigación y diseño |
| Se aplica a | las sesiones de agente de este desarrollo | el producto y su plan |
| Herramienta que usa | git, worktrees, OpenSpec, CI, estos scripts | — |

**Quipu no se desarrolla con Quipu.** No es viable arrancar el producto para poder
construirlo, y ningún documento de aquí debe suponerlo. Donde una regla dependa de que
Quipu esté corriendo, es una aspiración, no una norma, y hay que marcarla como tal.

Lo que la investigación de `conocimiento/investigacion/` aporte al **método** se importa
aquí explícitamente, reescrito como norma. Lo que aporte al **producto** no entra: va al
plan.

## Estructura

| Ruta | Qué fija |
|---|---|
| `AGENTS.md` | contrato de entrada, orden de lectura, reglas de oro, nivel de autonomía |
| `SESION-EJECUCION.md` | la sesión orquestadora: frontera planeación/ejecución y reparto de roles |
| `metodologia/normativa/CONSTITUCION.md` | reglas no negociables, en formato EARS |
| `metodologia/normativa/ESCALAMIENTO.md` | clases A/B/C: qué decide el agente y qué para al humano |
| `metodologia/normativa/VALIDACION.md` | tipos de evidencia válidos y Definición de Hecho |
| `metodologia/normativa/HANDOFF.md` | contrato de checkpoint entre sesiones, impuesto por `scripts/checkpoint.sh` |
| `metodologia/agents/` | roles genéricos: ejecutor, orquestador, verificador |
| `workflows/` + `skills/` | flujo OpenSpec genérico |
| `scripts/` | herramental: ledger, verificación, modo sombra, métricas |
| `contexto/` | contexto de producto que las tareas inyectan (no es normativa) |
| `adapters/` | perfiles opcionales por harness — sólo si usas ese harness |
| `archivo/` | histórico, no gobierna nada |

## Dónde escriben los scripts

`scripts/` vive aquí pero el ledger y las líneas base viven en el repositorio de
ejecución. La resolución por omisión es el hermano `../ejecucion`; se cambia con
`QUIPU_EJECUCION`, y las rutas concretas con `QUIPU_PROGRESS` y `QUIPU_SOMBRA`.

```bash
metodologia/scripts/estado.sh          # proyección compacta del ledger
QUIPU_EJECUCION=/otra/ruta metodologia/scripts/estado.sh
```

## Cómo se cambia esta metodología

Ningún agente la edita: `metodologia/normativa/CONSTITUCION.md` regla 12. La modifica el humano, en
una sesión que no es de ejecución, y el historial de este repositorio es el registro de
cómo cambió. Un cambio que afecte a una fase abierta se anuncia en el ledger antes de
aplicarse: los prefijos ya inyectados no se recargan solos.
