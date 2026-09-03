# propose — crear la propuesta completa de un change (solo planificación)

Crea el change y todos sus artefactos en un paso: `proposal.md`, delta de
`specs/<capability>/spec.md`, `design.md`, `tasks.md`.

1. Entiende la petición; si hay ambigüedad material (alcance, comportamiento observable,
   compatibilidad, aceptación), pregunta antes de crear nada. Deriva un nombre kebab-case.
2. Crea el change (`openspec new change "<nombre>"`) y genera los artefactos según el
   esquema del proyecto. `<capability>` es el directorio de spec relativo a `specs/`;
   respeta la organización existente.
3. Revisa qué capabilities afecta; cada escenario del delta debe citar su test futuro.
4. **Para aquí.** No implementes en la misma sesión aunque la petición original lo pida.
   Anuncia: "Artefactos listos para revisión. Pide `apply` cuando quieras implementar."
