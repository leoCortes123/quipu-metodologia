# VALIDACION.md — qué significa "terminado"

## Tipos de evidencia válidos en F0

| Tipo | Qué es | Cómo se produce |
|---|---|---|
| `command_output` | salida + exit code de un comando dentro del contenedor | el Verificador lo re-ejecuta, no confía en la transcripción |
| `diff_review` | diff de git contra `main` evaluado contra criterios | `git diff` en la worktree |
| `file_content` | contenido final de un archivo creado/modificado | lectura directa |
| `veredicto_mecanico` | JSON de los pasos binarios del protocolo (CI, regla suite-diff, alcance tocado vs. declarado, commits con mensaje literal) | `bin/verificar.sh <tarea> <worktree>` con `QUIPU_VERIF_DETERMINISTA=1`; derivado y reproducible, **nunca escrito a mano** |

Cualquier otra cosa (narrativa, "debería pasar", captura sin comando) **no es evidencia**.

`QUIPU_VERIF_DETERMINISTA` tiene tres estados: `0` (apagado, por omisión — el Verificador
hace estos pasos a mano), `sombra` (el script observa y **no decide**: el Verificador hace
el protocolo completo igual y el Orquestador registra la comparación con
`metodologia/scripts/sombra.sh`) y `1` (vinculante). El paso de `sombra` a `1` exige 5 tareas
vivas consecutivas coincidiendo y ningún falso PASA, y **lo autoriza el humano**, no la
flota. Un solo falso PASA —el script aprueba y el juez rechaza por un hecho mecánico—
aborta el despliegue y devuelve el flag a 0.

Sobre `veredicto_mecanico`:

- **`FALLA` es vinculante**: la tarea está rechazada y no hay semántica que juzgar.
- **`PASA` no aprueba nada.** Sólo habilita al Verificador a entrar al paso 2 —juzgar los
  criterios GWT—, que sigue siendo suyo. El script nunca juzga semántica, y por eso no
  sustituye al Verificador ni roza la regla 14 de CONSTITUCION.
- El alcance declarado lo ensancha **únicamente** una resolución de ESCALAMIENTO que
  nombre el archivo. Que el Ejecutor se lo autodeclare en `archivos_tocados` no autoriza
  nada.
- Que el script diga `PASA` y el Verificador rechace por **semántica** no es un fallo del
  script: `PASA` nunca aprobó nada. Sólo cuenta como falso PASA si el rechazo es por un
  hecho **mecánico**, de los que el script sí mira.

## Puerta general (aplica a toda tarea F0)

- DADO el paquete de trabajo de una tarea, CUANDO el Verificador re-ejecuta los comandos
  que ella especifica, ENTONCES cada uno termina 0 con la salida esperada.
- DADO cualquier cambio, CUANDO corre el CI completo
  (`docker compose exec api composer ci` && `docker compose exec web pnpm run ci`),
  ENTONCES está verde.
- DADO la suite existente antes de la tarea (baseline), CUANDO corre después,
  ENTONCES ninguna suite que pasaba deja de pasar (regla suite-diff).

## Definición de Hecho por tarea

Una tarea está `hecha` sólo cuando:
1. Todos sus criterios GWT verificados por el Verificador (sesión distinta al Ejecutor).
2. CI completo verde.
3. Commit(s) realizados con el mensaje especificado.
4. Checkpoint escrito (`metodologia/normativa/HANDOFF.md`) con evidencia referenciada.
5. Cero archivos tocados fuera del alcance declarado (`git status --porcelain` limpio
   respecto a lo declarado).

## Lo que NO cuenta como terminado

- "Los tests pasan en mi sesión" sin re-ejecución del Verificador.
- CI verde con suites desactivadas/saltadas (CONSTITUCION regla 10).
- Cambios "de paso" no pedidos (van a checkpoint como hallazgo, no se aplican).
