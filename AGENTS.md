# AGENTS.md — Metodología de desarrollo de Quipu (agnóstica al harness)

Contrato de entrada para cualquier agente que trabaje en el desarrollo de Quipu,
con cualquier harness o modelo (opencode, claude, codex u otro). Humano propietario:
Leonardo. Este paquete sustituye tu criterio cuando él no está revisando: actúa sólo
dentro de lo que estos archivos permiten.

## Los cuatro repositorios (rutas relativas a `quipuNewVersion/`)

| Repositorio | Rol | Tu acceso |
|---|---|---|
| `QUIPU_ENTERPRISE/` | **el producto**. Todo el trabajo de código y specs ocurre aquí | escritura, dentro del reparto de tu tarea |
| `metodologia/` | **este contrato**: normativa, roles, workflows, scripts | lectura. Nunca lo editas (CONSTITUCION 12) |
| `ejecucion/` | la fase activa, el ledger, la evidencia y el estado | escritura: tu checkpoint y tu evidencia |
| `conocimiento/` | investigación, memoria de decisiones y **el plan completo** | ninguno, salvo que tu tarea lo autorice |

Del plan completo no ves nada: sólo tu fase, publicada en `ejecucion/fase-activa/`. Si
crees que el plan debería ser otro, eso es planeación — clase C, para y consulta.

Cliente futuro (`chasqui_n8n`) y v1 archivada (`QUIPU`): fuera de alcance, ni leer ni
tocar hasta que una fase lo autorice.

## Orden de lectura obligatorio

1. `metodologia/normativa/CONSTITUCION.md` — reglas no negociables
2. `metodologia/normativa/ESCALAMIENTO.md` — qué decides tú y qué escala al humano
3. `metodologia/normativa/VALIDACION.md` — qué significa "terminado"
4. El ExecPlan de tu fase: `ejecucion/fase-activa/F<n>-execplan.md`
5. TU tarea exacta: `ejecucion/fase-activa/tareas/T<nn>-*.md` — es autosuficiente: si algo
   que necesitas no está ni en ella ni arriba, es un caso de ESCALAMIENTO clase C

Nada más. No leas el resto del espejo ni los docs de diseño: contexto desperdiciado.
Lee `conocimiento/` solo si tu tarea lo autoriza explícitamente.

## Cómo usar tu harness (cualquiera vale)

Los roles de abajo son sesiones de trabajo, no una función propietaria de un
harness: sesión principal (orquesta), una sesión por tarea (ejecuta), sesión
distinta (verifica). Si tu harness soporta subagentes, úsalos; si no, abre sesiones
separadas con el mismo contrato. Las definiciones genéricas viven en
`metodologia/agents/`; los perfiles opcionales por harness en
`metodologia/adapters/` (solo si usas ese harness).

## Asignación de roles (sesiones reales)

| Rol FLOTA | Quién |
|---|---|
| Orquestador/Planificador | sesión principal: recibe la orden de fase, asigna tareas, consolida |
| Ejecutor | una sesión por tarea, en worktree propia, con SOLO su archivo de tarea |
| Verificador | sesión distinta del Ejecutor: valida criterios GWT y produce reporte |

Regla dura: **quien implementó nunca verifica su propio trabajo**.

## Nivel de autonomía vigente

**No hay fase activa.** F0 y F1 están cerradas (ver `ejecucion/ESTADO/CIERRE-F1.md`)
y el plan nuevo aún no está escrito. Mientras `ejecucion/fase-activa/` esté vacío,
ningún agente tiene alcance pre-aprobado: cualquier trabajo de desarrollo es
`metodologia/normativa/ESCALAMIENTO.md` clase C.

Cuando el humano abra una fase, sus tareas quedan **pre-aprobadas** por el hecho de
aprobar el plan: se opera en L3 dentro del alcance textual exacto de la tarea, y fuera de
ese texto rige `metodologia/normativa/ESCALAMIENTO.md`. No existe L4.

## Reglas de oro

1. Una tarea = una sesión = una worktree. Sin memoria previa: tu tarea lo contiene todo.
2. Los comandos corren DENTRO de los contenedores (`docker compose exec …`). Nunca php/pnpm del host.
3. Commits sólo cuando la tarea lo ordene, con el mensaje que la tarea especifique.
4. Si el CI está rojo, el código está mal. Nunca desactives lint/tests para pasarlo.
5. Todo lo escrito va en español (repo en español).
6. Antes de terminar: checkpoint (`metodologia/normativa/HANDOFF.md`) y evidencia (`metodologia/normativa/VALIDACION.md`).
7. La fuente de verdad de estado durante F0/F1 son los commits + `STATUS` en checkpoint;
   desde F1 la propia BD de Quipu **también** gobierna decisiones, invariantes y
   contradicciones (capability `decision-chain`: `decision`, `decision_supersede`,
   `invariante`, `contradiccion`, con sus gates en Postgres — promover una decisión y
   resolver una contradicción siguen siendo actos exclusivamente humanos). Las pantallas
   web de esta capa siguen pendientes (llegan en el dial F4).
