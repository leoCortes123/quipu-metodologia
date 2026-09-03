# ESCALAMIENTO.md — qué decides y cuándo paras

Responde las 4 preguntas en orden. La primera que dé "sí", manda:

| # | Pregunta | Si SÍ |
|---|---|---|
| 1 | ¿La acción está prohibida por CONSTITUCION o no cubierta por el texto exacto de tu tarea? | **CLASE C** |
| 2 | ¿Es irreversible, toca credenciales/producción, borra algo entero no especificado, o cambia dependencias (`composer.json`/`package.json`)? | **CLASE C** |
| 3 | ¿Requiere interpretar ambigüedad de negocio o elegir entre alternativas de diseño? | **CLASE C** |
| 4 | ¿Toca >3 archivos o >30 min de retrabajo si te equivocas? | **CLASE B** |

Si todas son NO → **CLASE A**: procede.

## Qué significa cada clase

### Clase A — autónomo con registro
Procede. Registra la decisión en tu checkpoint (`decisiones_tomadas`), con cita a la
regla o criterio que la justifica. No preguntes nada. Ejemplos: nombre de variable,
orden de imports, texto de un mensaje de error, dividir un paso en subcomandos.

### Clase B — autónomo notificando
Procede con la opción más conservadora (la que menos cosas mueve). Deja la decisión
marcada en `abierto[]` del checkpoint para revisión humana posterior. Ejemplos:
resolver un conflicto de merge trivial, reordenar commits de una tarea, ampliar un
mensaje de documentación.

### Clase C — requiere humano. Para y consulta.
No avances ni "de mientras". Redacta la consulta así y detente:

```
ESCALAMIENTO C — <tarea>
Hecho hasta ahora: <1-3 líneas>
Decisión requerida: <una pregunta cerrada, sí/no o entre opciones A/B>
Opciones:
  A) <…> — consecuencia: <…>
  B) <…> — consecuencia: <…>
Recomendación: <A|B> porque <1 línea, citando regla/evidencia>
```

Ejemplos F0: cuál de `AdopcionTest`/`AdoptionTest` sobrevive si ambas tienen tests únicos;
aceptar o rechazar un hallazgo inesperado del inventario; cualquier cosa fuera de T01–T06.

## Anti-patrones prohibidos

- Preguntar en clase A/B (ruido: agota al humano y no protege nada).
- Avanzar en clase C "para mostrar progreso".
- Reformular una pregunta C como acción ya ejecutada ("hice X, ¿lo revierto?").
