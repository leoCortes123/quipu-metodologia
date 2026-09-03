# CONSTITUCION.md — reglas no negociables (semilla)

Formato: declaraciones EARS. Vigencia: desde F0. Cuando la capability `decision-chain`
(F1) aterrice, estas reglas se migran a la BD de Quipu y este archivo pasa a export
derivado — nunca se edita para cambiar su sentido: se registra decisión que la supersede.

## Identidad del proyecto

EL PROYECTO ES Quipu Enterprise: gestor de proyectos con Web UI, API REST y servidor MCP
cuya lógica de negocio vive en PostgreSQL. El repo entero —comentarios, docs, mensajes de
error— ESTÁ EN ESPAÑOL.

## Reglas estructurales

1. EL SISTEMA DEBERÁ imponer cada regla del método primero como trigger, función PL/pgSQL o CHECK en Postgres; sólo si no puede, en PHP.
2. UN ESTADO INVÁLIDO NUNCA DEBERÁ ser posible: la UI esconde el botón, la API devuelve 422 y Postgres rechaza la fila.
3. EL SISTEMA NUNCA DEBERÁ exponer una tool MCP que apruebe bloques, autorice cambios o promueva decisiones: aprobar es acto humano (`block.approve` sólo `human_admin`).
4. TODO rechazo DEBERÁ salir como 422 (el estado no lo permite para nadie) o 403 (falta un permiso, y el mensaje lo nombra). Nunca un 500 con SQL dentro.
5. HUMANOS Y AGENTES DEBERÁN pasar por los mismos gates: no existe puerta de servicio para agentes.
6. UN CAMPO DE TEXTO LIBRE SÓLO DEBERÁ contener información dirigida a un humano. Si hay que leer prosa para saber qué hacer, es un defecto de modelado.

## Reglas del flujo de desarrollo

7. LA ESPECIFICACIÓN EN `openspec/specs/` DEBERÁ mandar sobre cualquier otro documento; donde discrepen, manda la spec (y el código y sus tests sobre la spec heredada).
8. NINGÚN change SE ARCHIVARÁ sin su delta sincronizado; CADA escenario DEBERÁ citar el test que lo verifica.
9. EL CI DEBERÁ estar verde (`docker compose exec api composer ci` + `docker compose exec web pnpm run ci`) antes de dar cualquier cambio por hecho.
10. NADIE DESACTIVARÁ una regla de lint o un test para que el CI pase.
11. UNA MIGRACIÓN YA APLICADA NUNCA SE EDITARÁ: se escribe una nueva.
12. NINGÚN AGENTE MODIFICARÁ `metodologia/normativa/CONSTITUCION.md`, ni las ideas 1–4 documentadas en el README del producto, ni el contenido normativo de una spec existente.

## Reglas de trabajo agéntico

13. UN EJECUTOR NUNCA TOCARÁ archivos fuera del reparto declarado en su tarea.
14. QUIEN IMPLEMENTÓ NUNCA VERIFICARÁ SU PROPIO TRABAJO.
15. ANTE DUDA ENTRE AVANZAR Y ESCALAR, EL AGENTE ESCALARÁ (`metodologia/normativa/ESCALAMIENTO.md`).
