#!/usr/bin/env bash
# checkpoint.sh — valida y anexa checkpoints al ledger (Sistema A).
#
# El contrato de HANDOFF.md era una convención: nadie lo imponía y el ledger derivó a 42
# claves distintas y `veredictos` en prosa. Esto lo hace mecánico (idea 3 de CLAUDE.md):
# una entrada inválida no está desaconsejada, no entra.
#
# Uso:
#   checkpoint.sh validar <ruta.json|->      # valida; exit 0 si cumple, 1 si no
#   checkpoint.sh anexar  <ruta.json|->      # valida y, sólo si pasa, anexa al ledger
#   checkpoint.sh auditar [ledger]           # informe de deriva del ledger existente
#
# `anexar` es la única vía de escritura del Orquestador. El ledger es append-only: esto
# jamás reescribe ni reordena lo ya escrito.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# El ledger y las líneas base viven en el repositorio de ejecución (hermano de este).
EJEC="${QUIPU_EJECUCION:-$RAIZ/../ejecucion}"
LEDGER="${QUIPU_PROGRESS:-$EJEC/sesiones/progress.json}"
CMD="${1:-}"; ARG="${2:-}"

case "$CMD" in
  validar|anexar|auditar) ;;
  *) echo "checkpoint.sh validar|anexar <ruta.json|-> · checkpoint.sh auditar" >&2; exit 2 ;;
esac

# El script de python entra por stdin, asi que `-` no puede leer del pipe ahi:
# se vuelca a un temporal y se le pasa la ruta.
if [[ "$ARG" == "-" ]]; then
  TMP_CKPT="$(mktemp)"
  trap 'rm -f "$TMP_CKPT"' EXIT
  cat > "$TMP_CKPT"
  ARG="$TMP_CKPT"
fi

CMD="$CMD" ARG="$ARG" LEDGER_REAL="$LEDGER" python3 - <<'PY'
import json, os, sys, datetime

E = os.environ
cmd = E["CMD"]

# ── contrato (HANDOFF.md) ───────────────────────────────────────────────────
ROLES = ("ejecutor", "verificador", "orquestador")
ESTADOS = {
    "ejecutor":    ("hecha", "parcial", "bloqueada-escalamiento", "fallida"),
    "verificador": ("hecha", "fallida"),
    "orquestador": ("en-curso", "cerrada", "retrabajo", "detenida", "hecha"),
}
OBLIGATORIOS = ("tarea", "rol", "estado")
COMUNES = {
    "tarea": str, "rol": str, "estado": str, "ciclo": int, "worktree": str,
    "fecha": str,
    "commits": list, "archivos_tocados": list, "decisiones_tomadas": list,
    "evidencia": list, "abierto": list, "hallazgos_no_aplicados": list,
    "resolucion_escalamiento": str, "reemplaza_a": str, "siguiente_paso": str,
    "extra": dict,
}
SOLO_VERIFICADOR = {"commits_verificados": list, "veredictos": list}
PERMITIDOS = {**COMUNES, **SOLO_VERIFICADOR}
TIPOS_EVIDENCIA = ("command_output", "diff_review", "file_content", "veredicto_mecanico")
RIESGOS = ("bajo", "medio", "alto")

def primer_token(estado):
    return (estado or "").strip().split()[0].lower().strip("—-(),") if estado else ""

def valida(e, i=None):
    """Devuelve la lista de incumplimientos de UNA entrada."""
    d = f"[{i}] " if i is not None else ""
    if not isinstance(e, dict):
        return [f"{d}la entrada no es un objeto JSON"]
    fallos = []

    for k in OBLIGATORIOS:
        if not e.get(k):
            fallos.append(f"{d}falta el campo obligatorio `{k}`")

    rol = e.get("rol")
    if rol and rol not in ROLES:
        fallos.append(f"{d}rol `{rol}` no es uno de {'/'.join(ROLES)}")

    if rol in ESTADOS and e.get("estado"):
        tok = primer_token(e["estado"])
        if tok not in ESTADOS[rol]:
            fallos.append(f"{d}estado `{tok}` no vale para el rol {rol}; "
                          f"admitidos: {', '.join(ESTADOS[rol])}")

    for k, v in e.items():
        if k not in PERMITIDOS:
            fallos.append(f"{d}clave `{k}` fuera del contrato: va dentro de `extra`")
            continue
        if k in SOLO_VERIFICADOR and rol != "verificador":
            fallos.append(f"{d}`{k}` es sólo del verificador, no de {rol}")
        esperado = PERMITIDOS[k]
        if esperado is int and isinstance(v, bool):
            fallos.append(f"{d}`{k}` debe ser entero, no booleano")
        elif not isinstance(v, esperado):
            fallos.append(f"{d}`{k}` debe ser {esperado.__name__}, "
                          f"no {type(v).__name__}")

    # veredictos: estructura, no prosa. Es el defecto que motivó el contrato.
    ver = e.get("veredictos")
    if isinstance(ver, list):
        for j, v in enumerate(ver):
            if not isinstance(v, dict):
                fallos.append(f"{d}veredictos[{j}] es prosa; debe ser "
                              "{criterio, resultado, evidencia}")
                continue
            if v.get("resultado") not in ("CUMPLE", "NO CUMPLE"):
                fallos.append(f"{d}veredictos[{j}].resultado debe ser CUMPLE o NO CUMPLE")
            for req in ("criterio", "evidencia"):
                if not v.get(req):
                    fallos.append(f"{d}veredictos[{j}] sin `{req}`")

    for j, x in enumerate(e.get("evidencia") or []):
        if not isinstance(x, dict):
            fallos.append(f"{d}evidencia[{j}] no es objeto")
        elif x.get("tipo") not in TIPOS_EVIDENCIA:
            fallos.append(f"{d}evidencia[{j}].tipo `{x.get('tipo')}` no es válido; "
                          f"VALIDACION.md admite: {', '.join(TIPOS_EVIDENCIA)}")

    for j, x in enumerate(e.get("abierto") or []):
        if not isinstance(x, dict):
            fallos.append(f"{d}abierto[{j}] no es objeto")
        else:
            if not x.get("pregunta"):
                fallos.append(f"{d}abierto[{j}] sin `pregunta`")
            if x.get("riesgo") not in RIESGOS:
                fallos.append(f"{d}abierto[{j}].riesgo debe ser {'/'.join(RIESGOS)}")

    for j, x in enumerate(e.get("decisiones_tomadas") or []):
        if not isinstance(x, dict) or not all(x.get(k) for k in ("que", "por_que", "cita")):
            fallos.append(f"{d}decisiones_tomadas[{j}] debe traer que, por_que y cita")

    # VALIDACION.md: `hecha` sin evidencia referenciada es inválido.
    if rol in ("ejecutor", "verificador") and primer_token(e.get("estado", "")) == "hecha" \
       and not (e.get("evidencia") or e.get("veredictos")):
        fallos.append(f"{d}`hecha` sin evidencia referenciada (VALIDACION.md)")

    return fallos

# ── auditar: informe sobre el ledger existente, sin fallar ──────────────────
if cmd == "auditar":
    ruta = E["ARG"] or E["LEDGER_REAL"]
    try:
        entradas = json.load(open(ruta, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as err:
        print(f"checkpoint.sh: no puedo leer el ledger ({ruta}): {err}", file=sys.stderr)
        sys.exit(3)
    total = len(entradas)
    conformes, incumplen = 0, []
    for i, e in enumerate(entradas):
        f = valida(e, i)
        if f:
            incumplen.append((i, e.get("tarea", "?"), e.get("rol", "?"), f))
        else:
            conformes += 1
    print(f"Auditoría del ledger — {ruta}")
    print(f"  {total} entradas · {conformes} conformes · {len(incumplen)} con deriva\n")
    motivos = {}
    for _, _, _, f in incumplen:
        for x in f:
            clave = x.split("`")[1] if "`" in x else x[:40]
            motivos[clave] = motivos.get(clave, 0) + 1
    print("Motivos más frecuentes:")
    for k, v in sorted(motivos.items(), key=lambda x: -x[1])[:12]:
        print(f"  x{v:<3} {k}")
    print("\nEl ledger es append-only: esto NO se corrige, se lee normalizado con "
          "estado.sh.\nEl contrato rige para las entradas nuevas.")
    sys.exit(0)

# ── validar / anexar: leen una entrada (o lista) de fichero o stdin ─────────
origen = E["ARG"]
if not origen:
    print("checkpoint.sh: falta la ruta del checkpoint (o `-` para stdin)", file=sys.stderr)
    sys.exit(2)
try:
    crudo = open(origen, encoding="utf-8").read()
    dato = json.loads(crudo)
except (OSError, json.JSONDecodeError) as err:
    print(f"checkpoint.sh: el checkpoint no es JSON válido: {err}", file=sys.stderr)
    sys.exit(2)

nuevas = dato if isinstance(dato, list) else [dato]
fallos = []
for i, e in enumerate(nuevas):
    fallos += valida(e, i if len(nuevas) > 1 else None)

if fallos:
    print("checkpoint.sh: el checkpoint NO cumple el contrato de HANDOFF.md\n", file=sys.stderr)
    for f in fallos:
        print(f"  - {f}", file=sys.stderr)
    print(f"\n  {len(fallos)} incumplimiento(s). No se anexó nada.", file=sys.stderr)
    sys.exit(1)

if cmd == "validar":
    print(f"checkpoint.sh: {len(nuevas)} entrada(s) conformes al contrato.")
    sys.exit(0)

# anexar: append-only, jamás reescribe lo anterior
ledger = E["LEDGER_REAL"]
try:
    previas = json.load(open(ledger, encoding="utf-8")) if os.path.exists(ledger) else []
    if not isinstance(previas, list):
        raise ValueError("el ledger no es una lista")
except (OSError, json.JSONDecodeError, ValueError) as err:
    print(f"checkpoint.sh: ledger ilegible, no anexo ({ledger}): {err}", file=sys.stderr)
    sys.exit(3)

for e in nuevas:
    e.setdefault("fecha", datetime.datetime.now().astimezone().isoformat(timespec="seconds"))
os.makedirs(os.path.dirname(ledger), exist_ok=True)
with open(ledger, "w", encoding="utf-8") as fh:
    json.dump(previas + nuevas, fh, ensure_ascii=False, indent=2)
print(f"checkpoint.sh: {len(nuevas)} entrada(s) anexada(s). "
      f"Ledger: {len(previas)} -> {len(previas) + len(nuevas)}.")
PY
