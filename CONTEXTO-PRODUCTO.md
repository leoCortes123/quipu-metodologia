# CONTEXTO-PRODUCTO.md — Quipu Enterprise (referencia del producto)

> El repo entero —comentarios, docs, mensajes de error— está en **español**. Escribe igual.

## Qué es este repositorio

**Quipu Enterprise**: gestor de proyectos con Web UI, API REST y servidor MCP cuya lógica de
negocio vive en PostgreSQL. Humanos y agentes son filas de `member` con token Sanctum y pasan por
los mismos gates: los primeros entran por la Web UI, los segundos por MCP o REST.

**La fuente de verdad de lo que el sistema hace es `openspec/specs/`.** Cuatro ideas gobiernan
todas las decisiones:

1. **La BD es almacenamiento tonto; el Protocol Engine es el cerebro.** Las reglas viven en
   triggers, funciones PL/pgSQL y CHECKs. Cambiar una regla del método nunca es migrar la BD a lo
   loco: primero se decide si Postgres puede imponerla.
2. **Humanos y agentes son indistinguibles.** Mismo backend, mismos gates, sin puerta de servicio.
3. **Los protocolos son mecánicos, no convenciones.** Un estado inválido no está desaconsejado:
   es imposible. La UI esconde el botón, la API devuelve 422 **y Postgres rechaza la fila**.
4. **Un campo de texto libre sólo contiene información dirigida a un humano.** Si hay que leer
   prosa para saber qué hacer, es un defecto de modelado: entregables (filas), criterios
   dado/cuando/entonces (filas).

## Entorno: todo corre en Docker

```bash
docker compose up -d
docker compose exec api php artisan migrate --seed   # sólo la primera vez
```

| Servicio | Dónde | Qué |
|---|---|---|
| `web` | http://localhost:5174 | Vite + React 19 — **se entra por aquí** |
| `api` | http://localhost:8001 | Laravel 12 / PHP 8.4 (REST + MCP) |
| `postgres` | `:5436` | PostgreSQL 16 (`quipu`, y `quipu_test` para tests) |
| `redis` | `:6382` | Redis 7 (vía **predis**, no phpredis) |

- El código va **montado** desde el host: editar un fichero se ve al momento. `vendor/` y
  `node_modules/` viven en volúmenes: si tocas `composer.json` o `package.json`, reinicia el
  servicio (`docker compose restart api|web`).
- Si la web da `502` en `/api/*`, el contenedor `api` no está vivo (`docker compose ps`).
- Ejecuta todo dentro del contenedor: el `php` del PATH no es el del proyecto.

```bash
# CI completo — tiene que estar verde antes de dar nada por hecho
docker compose exec api composer ci        # pint --test + phpstan nivel 8 + pest
docker compose exec web pnpm run ci        # eslint+prettier + tsc -b + vitest

# Un solo test
docker compose exec api ./vendor/bin/pest tests/Feature/WorkflowTest.php
docker compose exec web pnpm vitest run src/lib/status.test.ts

# Piezas sueltas
docker compose exec api composer format    # pint (escribe)
docker compose exec api php artisan quipu:index          # escanea code/ → clases, rutas, componentes
```

**Nunca desactives una regla de lint o un test para que el CI pase.** Si el CI se pone rojo, lo
que está mal es el código.

## Desarrollo con OpenSpec (flujo genérico, vale con cualquier harness)

La especificación vive en `QUIPU_ENTERPRISE/openspec/`; los cambios fluyen por deltas
que se sincronizan al cerrar (ver `metodologia/workflows/` para el paso a paso):

1. **propose** — propuesta + delta specs + tareas (revisa qué capacidades afecta).
2. Implementar siguiendo `tasks.md`; cada escenario del delta cita el test que lo verifica.
3. CI verde → evidencia real → **sync** + **archive**: las specs quedan al día o el
   change no se archiva.

Reglas duras del flujo:

- **Ningún cambio se archiva sin su delta sincronizado.**
- **Cada escenario cita su test.** `openspec validate --all --strict` comprueba la estructura;
  la veracidad la garantiza este hábito.
- Al añadir una regla, decide primero si puede ser trigger o CHECK en Postgres. Sólo si no puede,
  va en PHP.
- **La evidencia que cita un escenario vive en `evidencia/`** siguiendo su
  README: derivada, reproducible, nunca editada a mano.

> **Punto cero (2026-08):** las cuatro capabilities existentes fueron sincronizadas
> antes de instituir el flujo estricto; su historial de deltas no existe y NO se
> reconstruye. El historial delta arranca vacío desde ese acuerdo: todo change nuevo
> sigue el flujo propose→implementar→CI→sync→archive sin excepción.

## Arquitectura: dónde vive cada regla

Tres capas, y **la de abajo manda**:

```
Postgres (migrations)   funciones + triggers + CHECKs   ← la regla de verdad
    ↑
app/Protocol/           el motor en PHP                 ← orquesta, no duplica
    ↑
app/Http/Controllers/   REST  ─┐
app/Mcp/Tools/          MCP   ─┴─ dos transportes, el mismo motor
```

- **`app/Protocol/`** — el motor: `BlockStateMachine`, `WorkflowService`, `GateReport`,
  `CambioStateMachine`, `NecesidadService`, `RequisitoService`, `EnlaceService`,
  `AdopcionEngine`, entre otros.
- **`app/Mcp/`** — `Servers/QuipuServer.php` y las tools en `Tools/`. Dos transportes
  (`routes/ai.php`): HTTP en `/mcp` con `auth:sanctum` y STDIO (`mcp:start quipu`) identificándose
  con `QUIPU_AGENT_TOKEN`.
- **Las migraciones que contienen el motor** (no sólo tablas): `..._110200_create_protocol_engine_functions`,
  `..._110300_create_protocol_engine_triggers`, `..._104000_create_strict_done_gate`,
  y toda la cadena de demanda (`necesidad`, `cambio`, `requisito`, `enlace`, `linea_base`, …).

### Errores: 422 o 403, nunca 500

- **422** — el estado no lo permite para nadie (`ProtocolViolation` o trigger P0001 convertido en
  bootstrap/app.php, mensaje intacto).
- **403** — falta un permiso (`PermissionDenied`); el mensaje nombra siempre el permiso faltante.

### Invariantes que no se tocan

- **No existe ninguna tool MCP para aprobar.** Cerrar un bloque es humano (`block.approve` sólo
  `human_admin`, desde `/verification`). Hay un test que lo vigila.
- **Un criterio no se marca cumplido sin evidencia enlazada** (`trg_bac_before_met`).
- **Un bloque en `done` tiene sí o sí quién lo aprobó** (`ck_block_verified`), incluso ante un
  UPDATE directo por SQL.
- **Sólo humanos firman actos de gobierno** (firmas, sellos de línea base).

## Tests

Los tests de Feature corren contra PostgreSQL real (`quipu_test`) con `RefreshDatabase`: media
lógica vive en triggers, así que sobre SQLite no se estaría probando el sistema. PHPStan **nivel
8** sobre `app`, `database`, `routes`.

## Frontend (`code/web`)

React 19 + TypeScript + Vite + **Tailwind v4** (CSS-first) + **shadcn/ui** + lucide. TanStack
Query para estado de servidor, zustand para UI. Estilos en clases Tailwind, **sin ficheros CSS**;
clases semánticas OKLCH (`bg-background`, `text-muted-foreground`…) y `cn()` de `@/lib/utils`.
Convenciones completas: `metodologia/contexto/estilo-ui.md`.
