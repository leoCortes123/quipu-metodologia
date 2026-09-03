---
name: ui-change
description: Implementa y valida un cambio en la UI de forma rápida y eficiente.
default_agent: ui-builder
loop: 1
steps:
  - id: implementar
    prompt: |
      Implementa el siguiente cambio en la UI:
      {input}
      
      IMPORTANTE: 
      - Sigue las convenciones de estilo del proyecto
      - Mantén la consistencia con el sistema de diseño existente
      - Solo modifica los archivos necesarios para este cambio
      - Proporciona una breve explicación de lo que cambiaste

  - id: revisar
    agent: ui-reviewer
    condition: on_success
    prompt: |
      Revisa el código generado en el paso anterior. Busca:
      - Problemas de accesibilidad (roles ARIA, etiquetas, contraste de color)
      - Buenas prácticas de React (keys, memoización, hooks correctos)
      - Buenas prácticas de CSS (selectores eficientes, no !important innecesario)
      - Posibles errores de TypeScript (tipos incorrectos, props faltantes)
      - Consistencia visual con el resto de la aplicación
      
      Si encuentras algún problema, corrígelo directamente. Si no hay problemas, confirma que la revisión pasó exitosamente.
