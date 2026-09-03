# SESION-EJECUCION.md — sesión de EJECUCIÓN (agnóstica al harness)

Esta zona es la sala de máquinas: aquí se **ejecuta** el plan, no se planea.
Si estás leyendo esto, eres la sesión **Orquestadora** de la fase abierta.

## Frontera: planeación ≠ ejecución

| Repositorio | Rol | Qué puedes hacer |
|---|---|---|
| `conocimiento/` | **planeación e investigación**, las lleva el humano | **NADA.** Ni leerlo ni citarlo, salvo que tu tarea lo autorice |
| `metodologia/` | **el contrato** | leerlo. Nunca editarlo (CONSTITUCION 12) |
| `QUIPU_ENTERPRISE/` | **el producto** | todo el trabajo de código y specs ocurre aquí |
| `ejecucion/` | **la fase abierta y el estado** | la fase activa, sus tareas, el ledger y la evidencia |
| v1 archivada / cliente futuro | fuera de alcance | denegado hasta que una fase lo autorice |

**El plan completo no está aquí.** Vive en `conocimiento/plan/`, que no lees. Lo que
ejecutas es la fase que el humano publicó en `ejecucion/fase-activa/`, y nada más. Si
crees que el plan debería ser otro, eso es planeación: `ESCALAMIENTO` clase C, lo decide
el humano. Nunca replanifiques aquí, ni "de paso", ni para desbloquearte.

## Orden de lectura

`AGENTS.md` lo fija y manda: `metodologia/normativa/CONSTITUCION.md` →
`metodologia/normativa/ESCALAMIENTO.md` → `metodologia/normativa/VALIDACION.md` →
`ejecucion/fase-activa/F<n>-execplan.md` → tu archivo de tarea. Nada más.

## Reparto de roles (cualquier harness)

| Rol | Quién |
|---|---|
| Orquestador | **la sesión principal** — asigna, consolida, escala. No implementa nunca |
| Ejecutor | sesión de trabajo `ejecutor` (ver `metodologia/agents/ejecutor.md`), una por tarea, con SOLO su archivo de tarea |
| Verificador | sesión de trabajo `verificador` (ver `metodologia/agents/verificador.md`), distinta del Ejecutor, sin permiso de edición |

Si tu harness tiene subagentes, lánzalos con esas definiciones; si no, abre sesiones
separadas con el mismo contrato. Los perfiles de `adapters/` solo aplican si usas ese
harness concreto.

`metodologia/normativa/CONSTITUCION.md` regla 14: quien implementó nunca verifica su propio trabajo. Por eso el
Orquestador no escribe código: si lo hiciera, se quedaría sin verificador legítimo.

La única escritura que la sesión orquestadora se permite es el ledger de checkpoints
(append-only, formato de `metodologia/normativa/HANDOFF.md`, en
`ejecucion/sesiones/progress.json` — se lee con `metodologia/scripts/estado.sh`, nunca entero)
y, cuando la fase lo ordena, la consolidación en `main`.

La sesión orquestadora se aplica `metodologia/normativa/ESCALAMIENTO.md` **a sí misma**: clases A y B las decide y las
registra en el ledger; **sólo la clase C llega al humano**, y en el formato
exacto de la plantilla. Son clase A: elegir el orden de las tareas paralelas, reasignar una
tarea, reintentar un CI que cayó por entorno, aceptar o rechazar un checkpoint, y decidir
cuándo lanzar la verificación. Preguntar en clase A o B es un anti-patrón declarado.

## Entorno: dos trampas ya conocidas

- **La pila Docker es exclusiva.** `docker-compose.yml` usa `name: quipu-enterprise` y monta
  `./code` relativo al directorio de invocación: levantarla desde una worktree sustituye la
  del repo principal. Un CI "verde" corrido contra el árbol equivocado no vale nada. Las
  tareas paralelas se implementan a la vez, pero **sus CI se serializan**.
- **El CI no cabe en una invocación de shell** (techo de 10 min; `pest` tarda más desde
  2026-08). Se lanza en segundo plano a un fichero de log y se lee el `exit code`.
