# decisiones — el porqué de cómo trabajamos

Decisiones sobre el **método**, no sobre el producto. Las del producto viven en
`../../conocimiento/memoria/decisiones/`; confundirlas es el error que
`../README.md` § «Lo que esto NO es» previene.

Una decisión por archivo, `DEC-M<n>-<slug>.md`, con el mismo formato que el banco de
producto: estado, fecha, quién decide, origen, pregunta, opciones, decisión, porqué,
consecuencias, qué la invalidaría.

Una decisión no se edita para cambiar su sentido: se marca superada y se escribe la nueva.
Aquí es convención, no mecanismo — el método no corre sobre Quipu.

| Ficha | Asunto | Estado |
|---|---|---|
| `DEC-M1-configuracion-de-agente-canonica.md` | `.claude/` o `.opencode/` como perfil canónico | abierta |
| `DEC-M2-openspec-validate-strict.md` | abrir permiso de `node`/`npx` o declarar validación manual | abierta |
| `DEC-M3-docker-compose-restart.md` | `restart: "no"` en la pila de desarrollo | abierta |
