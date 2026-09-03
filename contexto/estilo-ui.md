# Reglas de UI y Estilo del Proyecto

> **REGLA DE ORO: No modificar ningún archivo hasta que el usuario lo indique explícitamente.**
> Ante la duda, preguntar. Nunca asumir que hay que implementar algo.

## Stack
- React 19 + TypeScript + Vite
- Tailwind CSS v4 (CSS-first, sin archivo de configuración)
- shadcn/ui (estilo New York, base neutral)
- Lucide para iconos
- next-themes para modo claro/oscuro

## Convenciones Generales
- Usa componentes funcionales con hooks en React
- Sigue el principio de responsabilidad única para componentes
- Los estilos van con clases de Tailwind; no crees archivos CSS separados
- Usa `cn()` de `@/lib/utils` para combinar clases condicionales
- Los componentes de UI base están en `@/components/ui/` (shadcn/ui)

## Sistema de Diseño

### Paleta de colores (OKLCH, base neutral)
- Fondo claro: `oklch(1 0 0)` (blanco puro)
- Fondo oscuro: `oklch(0.145 0 0)` (casi negro)
- Primario: `oklch(0.205 0 0)` (neutral oscuro)
- Muted: `oklch(0.97 0 0)` (gris muy claro)
- Destructive: `oklch(0.577 0.245 27.325)` (rojo-anaranjado)
- Borde: `oklch(0.922 0 0)` (gris claro)
- Sidebar: `oklch(0.985 0 0)` (casi blanco)
- Las variables CSS están definidas en `src/index.css`; usalas con las clases semánticas: `bg-background`, `text-foreground`, `text-muted-foreground`, `bg-primary`, `text-primary-foreground`, `bg-secondary`, `text-secondary-foreground`, `bg-destructive`, `text-destructive-foreground`, `border-border`, etc.

### Tipografía
- Fuente: system font stack (Tailwind default)
- Tamaños base: `text-sm` para cuerpo, `text-base` para contenido normal, `text-lg` para subtítulos, `text-2xl` para títulos de página
- Monoespaciada (`font-mono`) para IDs, código y paths

### Espaciado
- Tailwind spacing scale (basada en `rem`): `p-2`, `p-3`, `p-4`, `gap-2`, `gap-3`, `gap-4`, `space-y-3`, `space-y-6`
- Layout: `space-y-6` entre secciones, `space-y-3` dentro de una sección

### Bordes y radios
- `--radius: 0.625rem` (10px) — borde redondeado estándar
- `rounded-lg` para tarjetas y contenedores principales
- `rounded-md` para botones e inputs

### Breakpoints (Tailwind defaults)
- `sm`: 640px, `md`: 768px, `lg`: 1024px, `xl`: 1280px, `2xl`: 1536px

## Accesibilidad
- Todos los elementos interactivos deben tener roles ARIA apropiados
- Incluye `aria-label` en botones sin texto visible
- Asegura contraste de color mínimo 4.5:1 para texto normal
- Usa `aria-expanded` en elementos colapsables
- Usa `sr-only` para texto solo visible a lectores de pantalla

## Rendimiento
- Evita renderizados innecesarios con `React.memo` y `useMemo`
- Usa `lazy()` + `Suspense` para rutas (ya configurado en `routes.tsx`)
- Minimiza el uso de `!important` en CSS (no debería usarse con Tailwind)
- Prefiere `useQuery` de TanStack Query para datos del servidor

## Estructura de archivos
- Páginas: `src/pages/`
- Componentes compartidos: `src/components/`
- Componentes UI base (shadcn): `src/components/ui/`
- Hooks: `src/hooks/`
- Lógica de API: `src/lib/`
- Utilidades: `src/lib/utils.ts`
