# HANDOFF.md — contrato de checkpoint entre sesiones

Toda sesión (Ejecutor, Verificador, Orquestador) escribe su checkpoint **ANTES de
terminar** — nunca después, nunca "si hay tiempo". Destino: mensaje final de la sesión,
en el JSON de abajo; el Orquestador lo persiste en `ejecucion/sesiones/progress.json` del repo
(append-only: una entrada por tarea/sesión).

**El contrato es mecánico, no una convención** (idea 3 del README del producto). Se valida con
`metodologia/scripts/checkpoint.sh`, y el Orquestador anexa con `checkpoint.sh anexar`, que
rechaza lo que no cumpla. Una entrada inválida no está desaconsejada: no entra.

```json
{
  "tarea": "F0/T02",
  "rol": "ejecutor|verificador|orquestador",
  "worktree": "wt/f0-t02-dedup-tests",
  "estado": "hecha",
  "ciclo": 1,
  "commits": ["<sha corto>: primera línea del mensaje"],
  "archivos_tocados": ["code/api/tests/Feature/..."],
  "decisiones_tomadas": [
    {"que": "...", "por_que": "...", "cita": "<regla CONSTITUCION o criterio de tarea>"}
  ],
  "evidencia": [
    {"tipo": "command_output", "comando": "docker compose exec api composer ci", "resultado": "exit 0"}
  ],
  "abierto": [{"pregunta": "...", "riesgo": "bajo|medio|alto"}],
  "hallazgos_no_aplicados": ["cosas vistas y deliberadamente no tocadas"],
  "siguiente_paso": "..."
}
```

## Campos

`tarea`, `rol` y `estado` son obligatorios. El resto es opcional, pero **si aparece, va
con el nombre y la forma de aquí**.

| Campo | Forma | Quién |
|---|---|---|
| `tarea` | `F<n>/T<nn>` o etiqueta de fase (`F1/entorno`) | todos |
| `rol` | `ejecutor` \| `verificador` \| `orquestador` | todos |
| `estado` | ver enum por rol, abajo | todos |
| `ciclo` | entero: número de vuelta (1 = primera) | todos |
| `fecha` | ISO-8601; la pone `checkpoint.sh anexar` si falta | automático |
| `worktree` | ruta o `main (sin worktree)` | todos |
| `commits` | lista de `"<sha>: <asunto>"` — lo que se **declara** | ejecutor, orquestador |
| `commits_verificados` | lista de shas — lo que el Verificador **confirmó** | **sólo verificador** |
| `veredictos` | lista de `{criterio, resultado, evidencia}` | **sólo verificador** |
| `archivos_tocados` | lista de rutas | ejecutor |
| `decisiones_tomadas` | lista de `{que, por_que, cita}` | todos |
| `evidencia` | lista de `{tipo, ...}`; `tipo` según `metodologia/normativa/VALIDACION.md` | todos |
| `abierto` | lista de `{pregunta, riesgo}`, riesgo `bajo\|medio\|alto` | todos |
| `hallazgos_no_aplicados` | lista de textos | todos |
| `resolucion_escalamiento` | texto: cómo resolvió el humano una clase C | todos |
| `reemplaza_a` | texto: qué entrada anterior deja sin efecto | todos |
| `siguiente_paso` | texto | todos |
| `extra` | objeto libre — **todo lo demás va aquí** | todos |

### `estado` por rol

| Rol | Valores |
|---|---|
| ejecutor | `hecha` · `parcial` · `bloqueada-escalamiento` · `fallida` |
| verificador | `hecha` · `fallida` |
| orquestador | `en-curso` · `cerrada` · `retrabajo` · `detenida` · `hecha` |

Se admite un matiz tras el valor (`"hecha (cuarta vuelta: retrabajo #3)"`): lo que se
valida es el primer token. El matiz es para humanos; lo que la máquina lee es el token
y `ciclo`.

### `veredictos` es estructura, no prosa

Era el defecto que motivó este contrato. El Verificador emite un veredicto **por
criterio**, no un párrafo:

```json
"veredictos": [
  {"criterio": "superada sin arista rechaza", "resultado": "CUMPLE",
   "evidencia": "QueryException fn_decision_superada — DecisionChainTest:141"},
  {"criterio": "ciclo A-B-A rechaza", "resultado": "NO CUMPLE",
   "evidencia": "insert aceptado; sin CTE recursivo en fn_supersede_sin_ciclos"}
]
```

`resultado` es `CUMPLE` o `NO CUMPLE`. Un solo `NO CUMPLE` ⇒ tarea rechazada
(`metodologia/normativa/VALIDACION.md`). Si hay que leer prosa para saber si una tarea pasó, es un defecto de
modelado (idea 4 del README del producto).

### `extra`: la válvula de escape

Lo que no encaje en un campo del contrato va dentro de `extra`, no al nivel superior.
Así lo excepcional queda registrado sin ensuciar lo que las herramientas leen:

```json
"extra": {"pila_restaurada": true, "causa_raiz_de_la_lentitud": "volúmenes fríos"}
```

Si algo aparece en `extra` una y otra vez, es señal de que le falta un campo al contrato:
eso se decide y se añade aquí, no se normaliza a mano en cada script.

## Reglas

- El Verificador reconstruye estado desde checkpoint + git. Jamás desde narrativa.
- `estado: hecha` sin evidencia referenciada es inválido (`metodologia/normativa/VALIDACION.md`).
- Un hallazgo no aplicado que parezca clase C → también en `abierto[]`.
- El estado de la fase se lee con `metodologia/scripts/estado.sh`, no leyendo el ledger entero.

## Deuda: las 41 entradas anteriores a este contrato

El ledger es append-only y **no se reescribe**. Las entradas escritas antes del
31-08-2026 traen 42 claves distintas y `veredictos` en prosa. `estado.sh` las normaliza
al leer y `checkpoint.sh auditar` mide cuánto falta. El contrato rige de aquí en
adelante; el pasado se lee, no se corrige.
