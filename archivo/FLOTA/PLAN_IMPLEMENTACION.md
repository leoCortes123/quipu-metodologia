# PLAN_IMPLEMENTACION.md — optimización de contexto de la flota

> **Este plan NO es de Quipu.** Es del propio Sistema A: optimización de contexto y coste
> de la flota de agentes. Se ejecutó parcialmente y sin tareas que lo gobernaran (ver
> `ARCHIVO/TRABAJO-SIN-TAREA.md` § 1); su propia §6 registra las divergencias. Sus cinco
> pendientes vivos están consolidados en `ESTADO/DEUDA-F2.md` § D.
> Las rutas que cita con prefijo `sistema-a/` hoy se leen sin ese prefijo.

**Estado:** ejecutado parcialmente el 31-08-2026 — ver **§6 · Estado de ejecución**,
que registra qué se implantó, qué diverge de este plan y qué sigue pendiente.
**Fecha del plan:** 30-08-2026. **HEAD del plan:** `62178cc`. **HEAD tras ejecución:** `0955537`.
**Snapshot de telemetría:** copia de `opencode.db` tomada 2026-08-30T23:12:06-05:00
(mtime original 2026-08-30 12:10:41). 34 sesiones, 500 mensajes, 2.085 partes.

Este plan sustituye el orden de implantación del dictamen original. La Fase 0
**confirmó** la mayor parte de la auditoría, pero **refutó tres puntos** — uno de
ellos de la propia auditoría — y eso cambia qué se implementa y en qué orden.

---

## §0 · Fase 0 — verificación

Todas las cifras de esta sección son reproducibles con el SQL que las acompaña
sobre la copia del snapshot. Nada procede del dictamen ni de la auditoría.

### 0.1 Esquema real de `message` y `part`  → (c)

```
message: id, session_id, time_created, time_updated, data
part:    id, message_id, session_id, time_created, time_updated, data
```

No existen columnas `role` ni `type`: todo está en `data` (JSON).

```sql
-- La consulta de la Fase 0 del dictamen, literal:
select count(*) from message where session_id=? and role='assistant';
-- >>> ERROR: no such column: role
```

**Forma correcta:**

```sql
select count(*) from message
 where session_id = ?
   and json_extract(data,'$.role') = 'assistant';
```

**Campos de tokens disponibles por turno** (`message.data.tokens`):
`input`, `output`, `reasoning`, `cache.read`, `cache.write`, `total`.

Verificación de integridad ejecutada sobre los 429 turnos de asistente:

| Comprobación | Resultado |
|---|---|
| `input + output + reasoning + cache.read + cache.write == total` | **413 / 413** turnos con `total`; 0 discrepancias |
| Turnos sin campo `total` (abortados) | 16 |
| `session.tokens_*` == `sum(message.data.tokens.*)` | exacto en las 4 sesiones de pago |

**Consecuencias operativas, ambas verificadas y ambas necesarias para el resto del plan:**

1. `tokens_input` **excluye** `cache_read`. Por tanto `K/C = cache_read / (cache_read + tokens_input)`
   está bien definido y es la fracción de tokens de *prompt* servidos desde caché.
2. **`part.data` NO contiene conteos de tokens.** Contiene `state.output` (el texto).
   El coste en tokens de una salida de herramienta **hay que estimarlo por bytes** — o,
   mejor, deducirlo por diferencia con el `miss` del turno siguiente (ver 0.5).

> ⚠️ **Discrepancia con el dictamen (§13).** Afirma que el desglose de tokens por
> herramienta «está en `part.data`». Es falso: ahí está el texto, no los tokens.

### 0.2 Segmentación flota vs no-flota  → (a)

```sql
select count(*), sum(tokens_input), sum(tokens_cache_read),
       sum(tokens_output), sum(cost)
  from session
 where agent in ('orquestador','ejecutor','verificador');
```

| Segmento | n | miss (`input`) | hit (`cache_read`) | out | prompt | K/C | entrada:salida | coste |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| TODO (base entera) | 34 | 1.673.747 | 9.227.520 | 118.265 | 10.901.267 | 84,6 % | 92,2:1 | $0,042914 |
| **FLOTA (3 roles)** | **8** | **440.484** | **2.022.848** | **22.562** | **2.463.332** | **82,1 %** | **109,2:1** | $0,041162 |
| **FLOTA sobre DeepSeek** | **3** | **83.706** | **257.792** | **2.158** | **341.498** | **75,5 %** | **158,2:1** | $0,041162 |
| NO-FLOTA | 26 | 1.233.263 | 7.204.672 | 95.703 | 8.437.935 | 85,4 % | 88,2:1 | $0,001752 |

✅ **La auditoría queda confirmada al decimal**: flota = 8 sesiones, 82,1 %, 109,2:1.
El 84,6 % del dictamen es la base entera, que incluye 26 sesiones de `build`/`explore`/
`plan` sobre modelos gratuitos en `developTool`, `chasqui_n8n` y `/home/leonardo`.

**Hallazgo nuevo, no señalado por la auditoría, y es el que más limita el plan:**

| rol | modelo | sesiones | turnos de asistente |
|---|---|--:|--:|
| orquestador | DeepSeek (pago) | 2 | 9 |
| verificador | DeepSeek (pago) | **1** | **4** |
| ejecutor | DeepSeek (pago) | **0** | **0** |
| orquestador | gratis | 3 | 43 |
| ejecutor | gratis | 2 | 18 |

La ruta de producción son **3 sesiones y 13 turnos**, con **un solo Verificador** y
**ningún Ejecutor**. Toda afirmación sobre «la anatomía del Verificador» descansa
sobre n=1. Esto no invalida el plan, pero decide el método de medición (§3).

### 0.3 Composición del volumen de salida de herramienta  → (b)

```sql
select json_extract(p.data,'$.tool'),
       json_extract(p.data,'$.state.output'),
       json_extract(p.data,'$.state.input.filePath')
  from part p join session s on s.id = p.session_id
 where json_extract(p.data,'$.type') = 'tool'
   and s.agent in ('orquestador','ejecutor','verificador');
```

Total: **561.895 chars** en 8 sesiones.

| herramienta | chars | % bruto | llamadas | **% ponderado por turnos** |
|---|--:|--:|--:|--:|
| `read` | 478.542 | **85,2 %** | 49 | 87,8 % |
| `bash` | 67.299 | 12,0 % | 50 | **8,2 %** |
| resto | 16.054 | 2,8 % | 15 | 4,0 % |

Dentro de `read`: **`progress.json` = 267.496 ch = 55,9 % de `read` = 47,6 % del total.**

✅ **La auditoría queda confirmada exactamente**: read 85,2 %, progress.json 47,6 %.

**Corrección propia — el volumen bruto es la métrica equivocada.** Una salida emitida
en el turno *t* se reenvía en cada turno posterior; una emitida en el último turno no
se reenvía nunca. Ponderando por turnos de permanencia (5.343.143 ch·turno):

| familia | bruto | ponderado |
|---|--:|--:|
| `read:progress.json` | 47,6 % | **42,4 %** |
| `read:` otros archivos | 37,6 % | **45,4 %** |
| `bash` (CI, git) | 12,0 % | **8,2 %** |

`bash` aparece de media al 56 % de la sesión, así que sobrevive pocos turnos. Bajo la
métrica correcta, **el yacimiento de `bash`/CI es el 8,2 %**, no el 12 %.

Y por recurrencia (¿es una regla o un evento?):

| archivo | sesiones distintas | % de read | clase |
|---|--:|--:|---|
| `progress.json` | 4 | 55,9 % | **recurrente → atacable por regla** |
| `F1-execplan.md` | 5 | 9,6 % | recurrente |
| `AdoptionEngine.php` | 1 | 7,1 % | evento único |
| `CONSTITUCION.md` | 6 | 3,4 % | recurrente |
| `api.php` | 1 | 3,4 % | evento único |

**74,9 % del volumen de `read` es recurrente** (≥3 sesiones) y por tanto planificable.
22,2 % son eventos únicos que ninguna regla previene.

### 0.4 Tamaño real del paquete fijo  → (d)

`opencode.json` inyecta exactamente esto:

```json
"instructions": ["CLAUDE.md", "sistema-a/AGENTS.md"]
```

| archivo | bytes | ~tokens | ¿prefijo? |
|---|--:|--:|---|
| `CLAUDE.md` | 6.587 | 1.646 | **sí, inyectado** |
| `sistema-a/AGENTS.md` | 2.558 | 639 | **sí, inyectado** |
| `.opencode/agents/<rol>.md` | ~1.530 | ~390 | **sí, uno por sesión** |
| **PREFIJO REAL** | **10.705** | **≈ 2.676** | |
| `CONSTITUCION.md` | 2.444 | — | ❌ se lee con `read` |
| `ESCALAMIENTO.md` | 2.125 | — | ❌ se lee con `read` |
| `VALIDACION.md` | 1.755 | — | ❌ se lee con `read` |
| `HANDOFF.md` | 1.319 | — | ❌ se lee con `read` |
| `DESPLIEGUE.md` | 4.795 | — | ❌ se lee con `read` |

> ⚠️ **Discrepancia triple.** El dictamen da **16,8 KB** (§2) y **28,6 KB** (§13) —
> se contradice a sí mismo. **Mi propia auditoría dio 14,2–23,6 KB y también estaba
> mal**, porque sumó documentos que no se inyectan. El número correcto es **10.705 B
> (≈2.676 tokens)**, y el dictamen clasifica como «prefijo cacheable» cinco documentos
> que en realidad entran como *resultados de herramienta* — observado directamente en
> el turno 1 de la sesión más cara (0.5).

Esto importa porque **la palanca de T6 tal como está descrita —reordenar
`instructions`— actúa sobre 2.676 tokens.** No puede producir un 41–80 %.

### 0.5 Anatomía turno a turno de la sesión más cara

`ses_…KPqkqAKB` · orquestador · `deepseek-v4-pro` · $0,025462 · 7 turnos.

| turno | miss | hit | out | herramientas emitidas |
|--:|--:|--:|--:|---|
| 1 | 115 | 10.112 | 230 | CONSTITUCION(2.679) ESCALAMIENTO(2.395) VALIDACION(2.025) **progress.json(56.625)** |
| 2 | **20.953** | 10.496 | 84 | **progress.json(55.038)** |
| 3 | **17.417** | 31.488 | 84 | **progress.json(24.845)** |
| 4 | **8.123** | 48.896 | 132 | F1-execplan(9.202) T02(5.295) |
| 5 | 4.823 | 57.216 | 252 | bash(570) bash(511) |
| 6 | 411 | 62.464 | 259 | bash(1.016) bash(124) |
| 7 | 0 | 0 | 0 | task |

Tres lecturas del **mismo archivo** en tres turnos consecutivos. Los turnos 2–4, que
son exactamente los que siguen a cada relectura, concentran **46.493 de 51.842 tokens
miss = 89,7 %**.

**Ratio de tokenización calibrado** (turnos 3 y 4, donde `progress.json` es la única
fuente de contenido nuevo): 55.038 ch → 17.417 tok = **3,16 ch/tok**; 24.845 ch →
8.123 tok = **3,06 ch/tok**. JSON denso tokeniza a **≈3,1 ch/tok**, no a 4. Todas las
estimaciones de este plan usan 3,1 para JSON y 3,8 para markdown.

Atribución del gasto miss (**estimación**, salvo los turnos 3–4 que son exactos):

| origen | tokens miss | % de la sesión |
|---|--:|--:|
| `progress.json` (t2 parcial + t3 + t4) | ≈ 44.167 | **85,2 %** |
| resto | ≈ 7.675 | 14,8 % |

### 0.6 ¿Está roto el prefijo? — el hallazgo que cambia el plan

| sesión | rol | miss t1 | hit t1 | **K/C t1** | K/C sesión |
|---|---|--:|--:|--:|--:|
| KPqkqAKB | orquestador | 115 | 10.112 | **98,9 %** | 81,0 % |
| 10NcYs3Q | verificador | 10.334 | **0** | **0,0 %** | 62,0 % |
| 3Fz9TYID | orquestador | 10.227 | **0** | **0,0 %** | 40,3 % |
| 2LLDoBLI | plan | 12.471 | 0 | 0,0 % | 0,0 % |

En `KPqkqAKB` el prefijo cacheó al 98,9 % en el turno 1: **el 99,8 % de sus tokens
miss son contenido nuevo, no prefijo invalidado.**

> ⚠️ **Discrepancia con el dictamen (T6, puntuación 9,05, «implementar ya»).**
> Su tesis es que hay margen en la *higiene* del prefijo. Los datos dicen que cuando
> el prefijo está caliente cachea casi perfecto, y que el gasto viene de contenido
> nuevo. **T6 tal como está formulada no tiene margen.**
>
> Pero **sí hay un problema real y distinto**: dos de cuatro sesiones arrancaron
> **en frío** (0 % de acierto en el turno 1, ~10,3 k tokens a precio miss). Eso no se
> arregla reordenando `instructions`; se arregla **congelando el prefijo entre
> sesiones**, porque cualquier edición de `CLAUDE.md`, `AGENTS.md` o el `.md` del rol
> invalida el arranque de todas las sesiones siguientes. Durante F0/F1 esos archivos
> se estuvieron editando y redesplegando (`DESPLIEGUE.md` §1 documenta el `cp`).
> T6 sobrevive **reformulada**, con otra palanca y otra expectativa.

Reparto del miss de la flota DeepSeek (83.706 tok):

| componente | tokens | % |
|---|--:|--:|
| Relectura de `progress.json` (1 sesión) | ≈ 44.167 | **52,8 %** |
| Arranque en frío (2 sesiones × ~10,3 k) | 20.561 | **24,6 %** |
| Resto | ≈ 18.978 | 22,7 % |

### 0.7 Corrección al modelo de coste del dictamen (§3)

El dictamen afirma que «el coste es cuadrático en los turnos». Con caché activa eso
es falso. Eliminar un carácter que habría vivido *R* turnos ahorra **1 emisión a
precio miss + (R−1) reenvíos a precio hit**, y hit = miss/30 (`DESPLIEGUE.md` §2):

| R | ahorro en «miss-equivalentes» | aporte del reenvío |
|--:|--:|--:|
| 2 | 1,03 | 3,2 % |
| 4 | 1,10 | 9,1 % |
| 7 | 1,20 | 16,7 % |
| 12 | 1,37 | 26,8 % |

**El término dominante es la primera emisión.** El coste es ~lineal en volumen, no
cuadrático en turnos. Consecuencia para el plan: **lo que hay que evitar es emitir
contenido grande, no evitar que se reenvíe.** Eliminar un turno no ahorra «un contexto
entero»; ahorra su contenido nuevo.

El argumento de *calidad* (context rot) sí depende del volumen total del prompt y
**sobrevive intacto**. Es el argumento fuerte, no el económico.

### 0.8 Tareas y verdad de terreno  → (e)

```
TAREAS/F0: 7 archivos · TAREAS/F1: 7 archivos · TOTAL: 14
```

⚠️ El dictamen dice «las 13 tareas de F0 y F1». Son **14** archivos. Las 13 son las
claves distintas de `progress.json`, de las cuales **3 no son tareas**
(`F0/orquestacion`, `F1/entorno`, `post-F0/guia-usuario-y-chasqui`).

| métrica | valor |
|---|--:|
| Entradas en `progress.json` | 41 |
| Tareas F0/F1 con algún checkpoint | **10** |
| Entradas de rol `verificador` | 12 |
| …con `veredictos` + `commits_verificados` | **7** |
| …con veredicto **negativo** (`fallida`) | **1** (F0/T05) |

**El esquema de checkpoint ya derivó de `HANDOFF.md`:** el contrato documenta
`commits`, pero los verificadores escriben `commits_verificados`; y `veredictos` no
es una estructura sino **prosa libre**:

```
"veredictos": "6/6 CUMPLE (status vacío; 2 commits literales sobre c4879d8
 verificados con git log --format=%B carácter a carácter; ...)"
```

Consecuencia: **la verdad de terreno histórica no es comparable por máquina** sin
parsear prosa, y **existe un único ejemplo negativo** en toda la historia de la flota.
Esto acota duramente el Quipu-Bench (§4).

### 0.9 Duración medida del CI  → (f)

Cuatro fuentes independientes, dos de la telemetría y dos de los propios checkpoints:

| fuente | `composer ci` | `pnpm ci` |
|---|--:|--:|
| checkpoint F0/T01 (escala F0) | 51 s | 26 s |
| checkpoint F1/T00 | 307,32 s | 48,4 s |
| salida `time …` en telemetría | 305,1 s (`5m5,124s`) | — |
| salida con `COMPOSER_PROCESS_TIMEOUT` | 374,32 s | — |

**CI completo a escala F1 = 307 + 48 ≈ 355 s ≈ 5,9 min** (rango 5,1–7,0).
El dictamen dice «~7 min»: está en el extremo alto pero es defendible. Mi auditoría
dijo «5,1–6,2» refiriéndose solo a `composer`. **Cifra de planificación: 5,9 min.**

### 0.10 Resumen de discrepancias

| # | Afirmación | Origen | Veredicto Fase 0 |
|--:|---|---|---|
| 1 | Flota = 8 ses., 82,1 %, 109,2:1 | auditoría | ✅ confirmado |
| 2 | read 85,2 %, progress.json 47,6 % | auditoría | ✅ confirmado |
| 3 | `role` no existe en `message` | auditoría | ✅ confirmado |
| 4 | Paquete fijo 16,8 KB / 28,6 KB | dictamen | ❌ **ambas falsas** — son 10.705 B |
| 5 | Paquete fijo 14,2–23,6 KB | **auditoría** | ❌ **falsa** — sumó docs no inyectados |
| 6 | Desglose de tokens en `part.data` | dictamen | ❌ falso — solo texto |
| 7 | Coste cuadrático en turnos | dictamen | ❌ falso con caché — ~lineal |
| 8 | T6 tiene margen alto (9,05) | dictamen | ❌ **no en la higiene**; sí en arranque en frío (24,6 %) |
| 9 | 13 tareas F0+F1 | dictamen | ❌ son 14; 10 con checkpoint |
| 10 | `bash`/CI es el yacimiento (T7) | dictamen | ❌ 8,2 % ponderado; 3 de 5 CI ya usan `\| tail` |
| 11 | CI ~7 min | dictamen | ⚠️ 5,9 min medido |
| 12 | Ruta de pago tiene muestra suficiente | ambos | ❌ **n=3 sesiones, 13 turnos, 0 ejecutores** |

---

## §1 · Línea base recalibrada

**Segmento de referencia: flota (3 roles) sobre DeepSeek.** Es el único donde se gasta
dinero y donde corren los modelos de producción. Se declara con su n, siempre.

```sql
-- Consulta canónica de línea base. Ejecutar antes y después de cada ola.
select s.agent,
       count(*)                                   as sesiones,
       sum(s.tokens_input)                        as miss,
       sum(s.tokens_cache_read)                   as hit,
       sum(s.tokens_output)                       as out,
       round(1.0*sum(s.tokens_cache_read) /
             nullif(sum(s.tokens_cache_read)+sum(s.tokens_input),0), 4) as kc,
       round(sum(s.cost),6)                       as coste
  from session s
 where s.agent in ('orquestador','ejecutor','verificador')
   and json_extract(s.model,'$.id') like 'deepseek%'
 group by s.agent;
```

| KPI | Definición operativa | Consulta | Base medida | n |
|---|---|---|--:|--:|
| **MISS/sesión** ⭐ | `sum(tokens_input)` ÷ sesiones. Es el KPI principal: el miss cuesta 30× el hit, así que el coste *es* el miss. | canónica | **27.902** | 3 |
| **K/C turno 1** | `cache.read ÷ (cache.read+input)` del primer turno de asistente. Mide salud del prefijo. | §3.2 | **33,0 %** (98,9/0/0) | 3 |
| **K/C sesión** | ídem sobre la sesión completa. Diagnóstico, no meta. | canónica | **75,5 %** | 3 |
| **MISS por relectura** ⭐ | miss del turno *N* atribuible a un archivo ya emitido antes en la misma sesión. Objetivo directo de la Ola 1. | §3.3 | **≈44.167** (1 sesión) | 1 |
| **Aprobación al 1.er intento** | tareas con 0 retrabajos ÷ tareas verificadas. Canario de calidad. | §3.4 | 9/10 | 10 |

> **Advertencia sobre las metas.** No se fija ninguna meta derivada del 41–80 % de
> `arXiv:2601.06007` ni del >70 % de `arXiv:2607.07052`. El primero midió agentes de
> búsqueda web sobre OpenAI/Anthropic/Google **contra una línea base sin caché**;
> Quipu ya está en 75,5 % **con** caché, sobre DeepSeek, con carga de CI y código. El
> segundo es un preprint de autor único sobre AIOps de red. Ambos saltos de dominio
> son grandes. Las metas de este plan se derivan **solo** de la contabilidad de §0.

---

## §2 · Olas de implantación

Dos olas. La tercera queda **retirada** hasta que se cumpla una condición explícita.

### Ola 1 — Presupuesto y recuperación selectiva de `progress.json` (T5)

**Por qué primero:** es el 52,8 % del miss de la flota DeepSeek y el 42,4 % del
volumen de contexto ponderado. El dictamen la puso cuarta y en tercera ola; su propio
texto ya decía que era «el mayor bloque de contexto controlable de la flota».

**Paso 1.0 — prerrequisito (bloqueante).** Normalizar el esquema de checkpoint.
Hoy los verificadores escriben `commits_verificados` donde `HANDOFF.md` dice
`commits`, y `veredictos` es prosa. Sin esto el índice se construye sobre arena.

- Archivo: `sistema-a/HANDOFF.md` — añadir `veredictos` como array estructurado
  `[{criterio, resultado: CUMPLE|NO CUMPLE, evidencia}]` y aceptar
  `commits_verificados` como nombre canónico del rol verificador.
- Archivo: `sistema-a/.session/progress.json` — **no se reescribe** (append-only es
  invariante del método). Se añade un migrador de *lectura* que normaliza al vuelo.

**Paso 1.1 — índice.** `sistema-a/bin/progress-index.py` emite, por fase, una línea
por tarea con: `tarea, rol, estado, ciclo, commits, siguiente_paso`. Sin
`decisiones_tomadas`, sin `evidencia`, sin `hallazgos_no_aplicados`.

Tamaño previsto: 41 entradas × ~110 B = **≈4,5 KB ≈ 1.450 tokens**, frente a
123.726 ch ≈ **39.912 tokens** del archivo completo (**estimación** a 3,1 ch/tok).

**Paso 1.2 — protocolo.** `.opencode/agents/orquestador.md`, sección «Ciclo por tarea»:

```diff
-1. Lanza `@ejecutor` con: ruta exacta de la tarea + worktree a crear (según su encabezado).
+0. Lee el estado con `sistema-a/bin/progress-index.py <fase>`. NO leas
+   `.session/progress.json` completo. Si necesitas una entrada concreta, pídela con
+   `progress-index.py <fase> --tarea F1/T02`. Nunca releas el mismo archivo dos veces
+   en la misma sesión.
+1. Lanza `@ejecutor` con: ruta exacta de la tarea + worktree a crear (según su encabezado).
```

**Hipótesis falsable.** En la próxima sesión de orquestador que consulte estado de
fase, el *MISS por relectura* cae de ≈44.167 a **<6.000 tokens**.
**Umbral mínimo: <11.000** (≥75 % de reducción sobre ese componente). Se calcula por
contabilidad exacta (§3.3), no por comparación entre brazos.

**Criterio de salida.** 3 sesiones consecutivas de orquestador con MISS por relectura
<11.000 **y** cero escaladas nuevas atribuibles a falta de contexto.

**Criterio de ABORTO.** En 5 sesiones, ≥2 en las que el Orquestador pida el
`progress.json` completo, o ≥1 escalada clase C cuya causa registrada sea información
ausente del índice. Si eso ocurre, el índice está mal diseñado, no la técnica.

**Rollback en un paso.** `git revert` del commit que toca `orquestador.md`. El script
queda en el repo sin usarse. Cero estado que deshacer.

**Coste.**

| concepto | cantidad | origen |
|---|--:|---|
| Implantar (script + protocolo + HANDOFF) | ≈3 h · 1 sesión de ejecutor | estimación |
| Tokens de implantación | ≈40 k prompt / ≈2 k out ≈ **$0,012** | estimación por analogía con sesiones medidas |
| Medir | **0 tokens, 0 min de CI** | la medición es una consulta SQL sobre `opencode.db` |

### Ola 2 — Estabilidad de prefijo entre sesiones (T6, reformulada)

**Qué NO es.** No es reordenar `instructions`: el prefijo son 2.676 tokens y ya está
al principio. Reordenarlo no puede mover la aguja.

**Qué es.** Eliminar el arranque en frío. Dos de cuatro sesiones pagaron ~10,3 k
tokens a precio miss en el turno 1 con 0 % de acierto. La causa candidata es que el
prefijo cambió entre sesiones: `CLAUDE.md`, `sistema-a/AGENTS.md` y
`.opencode/agents/*.md` se editaron y redesplegaron durante F0/F1.

**Cambio concreto.**

- `sistema-a/DESPLIEGUE.md` §2 — añadir regla: *«Los archivos de prefijo
  (`CLAUDE.md`, `sistema-a/AGENTS.md`, `.opencode/agents/*.md`) son inmutables
  durante una fase. Toda edición se agrupa en el cierre de fase y se redespliega de
  una vez. Editar el prefijo a mitad de fase invalida el arranque en caché de todas
  las sesiones siguientes.»*
- `sistema-a/bin/prefijo-hash.sh` — imprime el SHA-256 del prefijo por rol; el
  Orquestador lo registra en el checkpoint de cierre de fase como evidencia
  `command_output`.

**Hipótesis falsable.** Con el prefijo congelado, la **2.ª y siguientes** sesiones de
un mismo rol dentro de una fase alcanzan **K/C turno 1 ≥ 90 %**.
**Umbral mínimo: ≥80 %.** (La 1.ª sesión tras un cambio de prefijo paga el frío
inevitablemente; queda excluida por definición.)

**Criterio de salida.** 3 sesiones no-primeras consecutivas con K/C t1 ≥80 % y hash de
prefijo constante.

**Criterio de ABORTO — importante.** Si con hash de prefijo **verificadamente
constante** el K/C del turno 1 sigue <50 % en 3 sesiones, entonces la causa **no es
nuestra**: es el TTL de la caché en disco de DeepSeek. En ese caso la ola se retira
sin más intentos y se documenta el hallazgo. No hay palanca del lado de Quipu.

**Rollback en un paso.** Borrar el párrafo de `DESPLIEGUE.md`. Es una regla de
proceso; no hay código que revertir.

**Coste.**

| concepto | cantidad | origen |
|---|--:|---|
| Implantar | ≈1 h | estimación |
| Tokens | ≈10 k ≈ **$0,003** | estimación |
| Medir | **0 tokens, 0 min de CI** | consulta SQL |

### Ola 3 — RETIRADA: gate determinista (T1+T7 fusionadas)

El encargo pedía fusionar T1 y T7 en un entregable. **Propongo no ejecutarlo todavía**,
y el motivo es la Fase 0, no la teoría:

1. **El yacimiento es el 8,2 %** del contexto ponderado (`bash`), no el 12 % bruto ni
   el «verdadero motor del gasto» que dice el dictamen.
2. **Ya está parcialmente explotado**: de las 5 invocaciones de CI registradas en
   toda la telemetría (4 × `composer ci`, 1 × `pnpm run ci`), **3 truncan la salida
   explícitamente** con `| tail -15` / `| tail -12` y producen 664–1.258 chars. De las
   2 que no truncan, una abortó pronto (798 ch) y solo una soltó los 40.340 ch — un
   diagnóstico con `time … -T` sin tubería, no el protocolo habitual.
3. **No hay a quién medírselo**: 0 sesiones de Ejecutor sobre DeepSeek y 1 de
   Verificador. El gate se diseñaría contra n=1.
4. Construirlo cuesta 3–5 días y su rollback es un flag, pero **su validación exige
   corridas de CI reales**, que es el único componente caro de todo este plan.

**Puerta de entrada explícita.** Se reabre cuando se cumplan las tres:
`bash` ≥25 % del contexto ponderado de la flota **y** ≥10 sesiones de Verificador
sobre DeepSeek registradas **y** ≥5 ciclos de retrabajo observados. Hasta entonces,
la regla barata equivalente es una línea en `verificador.md`: *«canaliza siempre la
salida de CI por `| tail -20`; si falla, pide el log completo por ruta»*, que captura
la mayor parte del beneficio con coste cero y sin gate que mantener.

---

## §3 · Instrumentación

### 3.1 Por qué la medición es contable y no inferencial

Variabilidad medida del miss por sesión:

| segmento | media | sd | CV |
|---|--:|--:|--:|
| flota DeepSeek (n=3) | 27.902 | 20.736 | 0,74 |
| flota completa (n=8) | 55.060 | 54.251 | 0,99 |

Tamaño de muestra para un A/B (t de dos muestras, α=0,05, potencia 0,80, CV=0,99):

| efecto a detectar | n por brazo | total |
|--:|--:|--:|
| 20 % | 388 | 777 |
| 30 % | 173 | 345 |
| 50 % | 62 | 124 |
| 70 % | 32 | 63 |

**La flota ha ejecutado 8 sesiones de rol en toda su historia.** Un A/B estadístico
es inviable por dos órdenes de magnitud, y ninguna cantidad de repeticiones lo
arregla dentro de F1–F2.

**Lo digo explícitamente, como se pidió: no se puede distinguir señal de ruido con
un diseño comparativo.** Por eso este plan **no propone ninguno**. Propone medición
contable: los tokens miss atribuibles a un archivo se **deducen exactamente** de la
base, apoyados en la identidad verificada en 413/413 turnos (§0.1). El efecto de
dejar de reemitir `progress.json` no se estima: se cuenta. Con n=1 basta, porque no
es una inferencia sobre una población, es una suma.

Lo que **no** se puede medir con esta muestra, y no se fingirá que sí:

- El efecto sobre **calidad** (context rot). Con 10 tareas y 1 veredicto negativo, la
  tasa de aprobación al primer intento no tiene resolución. Se registra como canario,
  no como evidencia.
- Cualquier comparación **entre modelos** o entre roles.

### 3.2 Consulta — K/C del primer turno

```sql
with t1 as (
  select m.session_id,
         json_extract(m.data,'$.tokens.input')      as miss,
         json_extract(m.data,'$.tokens.cache.read') as hit,
         row_number() over (partition by m.session_id order by m.time_created) as n
    from message m
   where json_extract(m.data,'$.role') = 'assistant'
)
select s.id, s.agent, t1.miss, t1.hit,
       round(1.0*t1.hit / nullif(t1.hit + t1.miss,0), 4) as kc_t1
  from t1 join session s on s.id = t1.session_id
 where t1.n = 1
   and s.agent in ('orquestador','ejecutor','verificador')
   and json_extract(s.model,'$.id') like 'deepseek%'
 order by s.time_created;
```

### 3.3 Consulta — MISS por relectura (KPI de la Ola 1)

El miss del turno *N* es el contenido nuevo introducido por las herramientas del
turno *N−1*. Atribuirlo a un archivo requiere cruzar `part` con el turno siguiente:

```sql
-- Emisiones de un mismo filePath más de una vez en la misma sesión = relectura.
select s.id, s.agent,
       json_extract(p.data,'$.state.input.filePath') as archivo,
       count(*)                                      as veces,
       sum(length(json_extract(p.data,'$.state.output'))) as chars
  from part p join session s on s.id = p.session_id
 where json_extract(p.data,'$.type') = 'tool'
   and json_extract(p.data,'$.tool') = 'read'
   and s.agent in ('orquestador','ejecutor','verificador')
 group by s.id, archivo
having veces > 1
 order by chars desc;
```

Los `chars` de la 2.ª emisión en adelante son la relectura evitable. Se convierten a
tokens con **3,1 ch/tok** (JSON) o **3,8** (markdown), ratio calibrado en §0.5.

### 3.4 Captura antes/después

- **Antes:** el snapshot de este plan ya es la línea base. Está fechado y es
  reproducible; no hay que ejecutar nada.
- **Después:** tras cada sesión real de la flota, correr 3.2 y 3.3 y anexar el
  resultado al checkpoint de cierre de fase como evidencia `command_output`, que es
  lo que `VALIDACION.md` acepta.
- **Sesiones necesarias:** **3 de orquestador** para el criterio de salida de la Ola 1;
  **3 no-primeras del mismo rol** para la Ola 2. Ambas cifras son criterios de
  estabilidad operativa, **no** potencia estadística — y se declaran como tales.

---

## §4 · Quipu-Bench, dimensionado

**El banco de 150 corridas del dictamen queda descartado.** Coste explícito, como se pidió:

| concepto | cálculo | total |
|---|---|--:|
| Corridas | 25 casos × 2 variantes × 3 repeticiones | 150 |
| CI | 150 × 5,9 min | **14,8 h** |
| Tokens | 150 × ~40 k prompt | ≈ **6,0 M** |
| Coste ≈ | 6,0 M mayormente a precio miss | ≈ **$1,5–2,5** (estimación) |

Frente a **$0,042914 gastados por la flota en toda su historia**: el banco costaría
**35–60× el gasto acumulado que pretende optimizar**. Con el modelo de coste del
propio dictamen, no se justifica.

**Además, el techo honesto de casos etiquetados es mucho menor de lo que se afirmó:**
10 tareas con checkpoint, 7 con veredicto, `veredictos` en prosa no comparable por
máquina, y **1 solo ejemplo negativo** en toda la historia. Un banco cuyo criterio
decisivo es «0 falsos PASA en el estrato adversarial» no tiene casos adversariales
naturales: habría que sintetizarlos todos.

### Banco propuesto, en tres niveles

| nivel | qué | casos | CI | tokens | cuándo |
|---|---|--:|--:|--:|---|
| **A — Contable** | Recalcular §3.2 y §3.3 sobre las sesiones históricas y las nuevas. Sin ejecutar nada. | 8 sesiones | **0 min** | **0** | ya, y tras cada sesión |
| **B — Replay dirigido** | Reejecutar la verificación de F0/T06 y F1/T02 (las 2 de evidencia más rica) antes y después de la Ola 1. | 2 × 2 = 4 | 4 × 5,9 = **24 min** | ≈160 k ≈ **$0,04** | al cerrar la Ola 1 |
| **C — Adversarial sintético** | 3 casos construidos: test desactivado, archivo fuera de alcance, `hecha` sin evidencia. Solo si algún día se construye el gate de la Ola 3. | 3 | **18 min** | ≈120 k ≈ **$0,03** | congelado |

**Presupuesto total del banco vivo (A+B): 24 min de CI y ≈$0,04.** El nivel B duplica
el gasto histórico de la flota, y eso se declara abiertamente: es el precio de tener
una comprobación de no-regresión, y es asumible. El nivel C no se paga hasta que la
Ola 3 pase su puerta de entrada.

---

## §5 · Riesgos

**R1 — El ahorro medido resulta indistinguible de cero.** *Probabilidad: baja para la
Ola 1, media-alta para la Ola 2.* La Ola 1 tiene una contabilidad exacta detrás: si el
Orquestador deja de emitir 34 k tokens, esos tokens no aparecen, y eso se lee en la
base. La Ola 2 depende de una causa que **no está probada**: atribuyo el arranque en
frío a ediciones del prefijo, pero podría ser el TTL de DeepSeek. Por eso su criterio
de aborto es explícito y barato de alcanzar. *Mitigación: la Ola 2 cuesta 1 h; si
aborta, se pierde 1 h y se gana un hecho documentado.*

**R2 — n=1 en el hallazgo principal.** El 52,8 % de miss atribuible a `progress.json`
procede de **una sola sesión**. Si la próxima sesión de orquestador no relee el archivo
tres veces, la palanca es más pequeña de lo estimado. *Mitigación: la Ola 1 no pierde
sentido aunque el efecto sea menor — el índice reduce el prompt en todos los casos —
pero la cifra prometida sí caería. Se declara como estimación de una muestra.*

**R3 — El índice omite lo que el siguiente agente necesitaba.** Es el riesgo real de
T5 y el dictamen lo señaló bien. *Mitigación: el índice nunca comprime campos
normativos (`commits`, `evidencia`, `decisiones_tomadas.cita`); solo los omite del
listado y los sirve bajo demanda por tarea. `append-only` se conserva: no se reescribe
ninguna entrada.*

**R4 — La normalización del esquema de checkpoint toca el contrato.** `HANDOFF.md` es
parte del método. *Mitigación: el cambio es aditivo (estructurar `veredictos`, aceptar
`commits_verificados`), no destructivo, y el migrador es de lectura. Ninguna entrada
existente se modifica.*

**R5 — Congelar el prefijo entra en conflicto con seguir desarrollando el método.**
Durante F1–F2 los agentes se están afinando. *Mitigación: el alcance del congelamiento
son 3 archivos y ~10,7 KB, no el paquete completo. `CONSTITUCION.md`, `VALIDACION.md`
y `ESCALAMIENTO.md` quedan fuera porque no están en el prefijo — pueden editarse
libremente.*

**R6 — Optimizar sobre una muestra de 13 turnos.** Es el riesgo de fondo de todo el
ejercicio. *Mitigación: ninguna de las dos olas es reversible con dificultad, ninguna
introduce un componente con estado, ninguna toca `code/`, y ninguna toca la regla 14
ni la topología. El coste de equivocarse es de horas, no de arquitectura.*

**R7 — Que el verdadero consumo esté fuera de `opencode.db`.** Las sesiones de Claude
Code del humano no están instrumentadas aquí, y por volumen podrían superar a la
flota. *No mitigado: queda declarado como hueco, igual que en el dictamen.*

---

## Cumplimiento de las restricciones duras

| restricción | cómo la respeta el plan |
|---|---|
| Regla 14 (quien implementó no verifica) | Ninguna ola toca el reparto de roles. La Ola 3, que era la única que rozaba el protocolo del Verificador, queda retirada. |
| Prohibición de cambiar de modelo | La Ola 2 **refuerza** esta regla: extiende la inmutabilidad del modelo a la inmutabilidad del prefijo entero. |
| Verificador irreducible | Intacto: `pro`, `subagent`, `edit: deny`, Default-FAIL. Ninguna poda topológica. |
| Cadena de 3 nodos, fan-out 1 | No se añade ni se elimina ningún agente. T2 y T4 no se resucitan. |
| El producto no llama a LLM | Verificado en Fase 0 (los positivos del grep eran «coherente»/«coherencia»). Nada de este plan toca `code/`. |

---

## §6 · Estado de ejecución (31-08-2026)

Registro de lo que se implantó realmente. Ordenado por divergencia con este plan: primero
lo que se apartó de él, porque es lo que hay que decidir.

### 6.1 Ola 3 se construyó pese a estar RETIRADA

El plan la retiró y fijó una puerta de entrada explícita de tres condiciones. **Ninguna se
cumple hoy**, y la medición del 31-08 lo confirma independientemente:

| Condición de reapertura | Umbral | Medido 31-08 |
|---|---|---|
| `bash` sobre contexto ponderado de la flota | ≥ 25 % | **17,5 % global; 5,1 % en el Verificador** |
| Sesiones de Verificador sobre DeepSeek | ≥ 10 | **1** |
| Ciclos de retrabajo observados | ≥ 5 | 4 en F1/T02, 2 en F0/T01 y F0/T05 |

Se construyó igual porque el encargo de la sesión lo pedía como Fase 1 y, al escalarse la
refutación de S3, el humano eligió la opción A —«progress.json primero, Fase 1 después»—,
es decir, la mantuvo en cola. Quedó entregado en `6d17f9e` (gate) y `ed2dab8` (modo sombra).

**Coste de tenerlo sin usarlo: cero.** `QUIPU_VERIF_DETERMINISTA` está en `0` por omisión y
el script se niega a correr; el `flota.sh` lo arranca en `sombra`, donde observa y no decide.
La racha viva está en 0/5 y no se enciende sola: pasar a vinculante es decisión humana.

**Sigue pendiente la alternativa barata que este plan proponía** y que no se hizo: la regla
de canalizar la salida de CI por `| tail -20` en `verificador.md`. Captura la mayor parte
del beneficio con coste cero y sin gate que mantener. Implantada en `verificador.md`.

### 6.2 Ola 1 se implantó SIN su Paso 1.0, que era bloqueante

Se entregó el índice (Paso 1.1) y el protocolo (Paso 1.2) como `sistema-a/bin/estado.sh`,
commit `7400111`. Resultado medido: **2.819 B frente a 125.030 B, −97,7 %**, dentro de lo
previsto por el plan (≈4,5 KB).

Pero el **Paso 1.0 —normalizar el esquema de checkpoint— no se hizo**, y el plan lo marcaba
bloqueante con razón. La deriva medida sobre las 41 entradas:

| Rol | Claves ajenas al contrato de `HANDOFF.md` |
|---|--:|
| orquestador | 15 |
| ejecutor | 9 |
| verificador | 8 |

Consecuencias concretas, no teóricas:

- **`estado.sh` pierde 7 confirmaciones de commit.** El Verificador escribe
  `commits_verificados`; `HANDOFF.md` dice `commits`; el índice lee `commits`. Resultado: la
  proyección muestra el commit que el Ejecutor *declara*, nunca el que el Verificador
  *confirmó*. Son hechos de distinto valor probatorio y hoy se ven iguales.
- **`veredictos` es prosa en 7 entradas**, así que el índice no puede mostrar CUMPLE/NO
  CUMPLE por criterio: exactamente la idea 4 de `CLAUDE.md` («si hay que leer prosa para
  saber qué hacer, es un defecto de modelado»).
- **`estado` tiene 9 valores distintos** donde `HANDOFF.md` fija 4. `estado.sh` normaliza al
  primer token conocido y guarda el resto como matiz; funciona, pero es una heurística
  tapando un defecto de contrato.

### 6.3 Fase 0 — confirmaciones cruzadas

La medición del 31-08 (`sistema-a/bin/metricas.sh`, línea base en
`.session/baseline-llm.json`) reproduce las cifras de cabecera del dictamen y **confirma
por segunda vía** las discrepancias 2 y 10 de §0.10: `read` domina (52,7 % del contexto
reenviado) y `progress.json` es el mayor archivo suelto; `bash`/CI no es el yacimiento.

Añade un dato que §0.2 ya apuntaba y conviene no perder: **sólo el 22,6 % del contexto
medido es de la flota**; el resto son agentes genéricos de opencode. Y la flota se portó a
Claude Code el 26-08, así que su actividad posterior no está en `opencode.db`.

### 6.4 Pendiente

| # | Qué | Por qué importa |
|--:|---|---|
| 1 | **Paso 1.0**: normalizar el esquema de checkpoint | bloqueante de Ola 1; ver §6.2 |
| 2 | **Ola 2** (estabilidad de prefijo entre sesiones) | sin empezar |
| 3 | §3.3: consulta de MISS por relectura | es el KPI que valida Ola 1; sin él, la mejora es teórica |
| 4 | Verificación de F1/T02 @ `3d86aaf` | cuarta vuelta cerrada por el Ejecutor, sin verificar |
| 5 | F1: T03, T04, T05, T06 | T03–T05 son las paralelizables: el estreno correcto del modo sombra |
