#!/usr/bin/env bash
# flota.sh — arranca la flota del Sistema A con el entorno correcto.
#
# Existe por una razón concreta: `QUIPU_VERIF_DETERMINISTA` tiene que estar puesto para
# que el modo sombra recoja datos, y un `export` que hay que recordar cada sesión es
# justo lo que no ocurre. Aquí queda fijado y documentado.
#
# Uso:
#   metodologia/scripts/flota.sh                 # arranca en modo sombra (lo normal ahora)
#   QUIPU_VERIF_DETERMINISTA=0 metodologia/scripts/flota.sh   # verificación a mano
#   QUIPU_VERIF_DETERMINISTA=1 metodologia/scripts/flota.sh   # vinculante — sólo tras 5/5
#
# El estado del despliegue se consulta con `metodologia/scripts/sombra.sh estado`; pasar a 1
# lo decide el humano, no la flota (VALIDACION.md).
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Modo sombra por omisión: el script observa y no decide. Ver VALIDACION.md.
export QUIPU_VERIF_DETERMINISTA="${QUIPU_VERIF_DETERMINISTA:-sombra}"

case "$QUIPU_VERIF_DETERMINISTA" in
  0|sombra|1) ;;
  *) echo "flota.sh: QUIPU_VERIF_DETERMINISTA='$QUIPU_VERIF_DETERMINISTA' no vale;" >&2
     echo "  usa 0 (apagado), sombra (observa) o 1 (vinculante)." >&2
     exit 2 ;;
esac

command -v opencode >/dev/null 2>&1 || {
  echo "flota.sh: no encuentro el ejecutable 'opencode' en el PATH." >&2
  exit 127
}

echo "Flota Sistema A — verificación determinista: $QUIPU_VERIF_DETERMINISTA" >&2
if [[ "$QUIPU_VERIF_DETERMINISTA" == "sombra" ]]; then
  "$RAIZ/metodologia/scripts/sombra.sh" estado >&2 || true
  echo >&2
fi

cd "$RAIZ"
exec opencode "$@"
