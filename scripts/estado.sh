#!/usr/bin/env bash
# estado.sh — proyección compacta del estado de la flota (Sistema A).
#
# `ejecucion/sesiones/progress.json` es el ledger de auditoría: append-only, crece sin techo
# y hoy pesa ~125 KB (~31 k tokens). Leerlo entero para saber "por dónde vamos" es
# el mayor consumidor de contexto de la flota (14 % de toda la salida de
# herramienta medida; ver metodologia/scripts/metricas.sh).
#
# Este script deriva de él la vista que los agentes sí necesitan —estado actual por
# tarea— y deja el detalle histórico a un paso de distancia, por tarea.
# NO escribe nada: el ledger no se toca.
#
# Uso:
#   metodologia/scripts/estado.sh                 # proyección compacta (texto)
#   metodologia/scripts/estado.sh --json          # la misma proyección, JSON
#   metodologia/scripts/estado.sh --tarea F1/T02  # detalle completo de UNA tarea
#   metodologia/scripts/estado.sh --abierto       # sólo lo que sigue abierto
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# El ledger y las líneas base viven en el repositorio de ejecución (hermano de este).
EJEC="${QUIPU_EJECUCION:-$RAIZ/../ejecucion}"
LEDGER="${QUIPU_PROGRESS:-$EJEC/sesiones/progress.json}"

if [[ ! -r "$LEDGER" ]]; then
  echo "estado.sh: no encuentro el ledger: $LEDGER" >&2
  exit 2
fi

QUIPU_LEDGER="$LEDGER" MODO="${1:---texto}" ARG="${2:-}" python3 - <<'PY'
import json, os, re, sys, collections

ledger = os.environ["QUIPU_LEDGER"]
modo   = os.environ["MODO"]
arg    = os.environ["ARG"]

try:
    with open(ledger, encoding="utf-8") as fh:
        entradas = json.load(fh)
except json.JSONDecodeError as err:
    print(f"estado.sh: el ledger no es JSON válido ({ledger}): {err}", file=sys.stderr)
    sys.exit(3)
if not isinstance(entradas, list):
    print(f"estado.sh: el ledger debe ser una lista de checkpoints, no {type(entradas).__name__}",
          file=sys.stderr)
    sys.exit(3)
entradas = [e for e in entradas if isinstance(e, dict)]
crudo = os.path.getsize(ledger)

# HANDOFF.md fija cuatro estados; el ledger real trae prosa ("hecha (cuarta vuelta…)",
# "CERRADA — ejecutor hecha + verificador APROBADA"). Normalizamos al primer token
# conocido y guardamos el resto como matiz corto, sin perderlo.
CANONICOS = ("hecha", "parcial", "bloqueada-escalamiento", "fallida",
             "en-curso", "cerrada", "fase-detenida-escalamiento-c")

def normaliza(estado: str):
    e = (estado or "").strip()
    bajo = e.lower()
    for c in sorted(CANONICOS, key=len, reverse=True):
        if bajo.startswith(c):
            matiz = e[len(c):].strip(" —-(),")
            return c, (matiz[:70] if matiz else "")
    return (bajo.split()[0] if bajo else "?"), e[:70]

# sha corto al principio de "3d86aaf: mensaje largo…" — el mensaje no viaja.
sha = lambda c: (re.match(r"\s*([0-9a-f]{7,40})\b", c or "") or [None, c]) and \
                (re.match(r"\s*([0-9a-f]{7,40})\b", c or "").group(1)
                 if re.match(r"\s*([0-9a-f]{7,40})\b", c or "") else (c or "")[:40])

# ── detalle de una sola tarea: aquí sí va todo ──────────────────────────────
if modo == "--tarea":
    if not arg:
        print("estado.sh --tarea <F1/T02>", file=sys.stderr); sys.exit(2)
    sel = [e for e in entradas if e.get("tarea") == arg]
    if not sel:
        print(f"estado.sh: sin entradas para «{arg}». Tareas: "
              + ", ".join(dict.fromkeys(e.get("tarea", "?") for e in entradas)),
              file=sys.stderr)
        sys.exit(1)
    print(json.dumps(sel, ensure_ascii=False, indent=2))
    sys.exit(0)

# El ledger derivó del contrato de HANDOFF.md: el Verificador escribe
# `commits_verificados` donde el contrato dice `commits`. Leer sólo `commits` hacía que
# la proyección enseñara lo que el Ejecutor DECLARA y nunca lo que el Verificador
# CONFIRMÓ —dos hechos de valor probatorio distinto—. Aquí se leen los dos y se
# distinguen; el ledger es append-only y no se reescribe.
ALIAS_VERIFICADOS = ("commits_verificados", "commits_confirmados")

def commits_de(entrada, claves):
    salida = []
    for c in claves:
        v = entrada.get(c)
        if isinstance(v, str):
            v = [v]
        salida += [sha(x) for x in (v or []) if x]
    return salida

# ── proyección: última entrada por (tarea, rol) ─────────────────────────────
orden, ultima, vueltas, pesado = [], {}, collections.Counter(), collections.Counter()
for i, e in enumerate(entradas):
    t = e.get("tarea", "?"); r = e.get("rol", "?")
    if t not in orden:
        orden.append(t)
    ultima[(t, r)] = (i, e)
    if r == "ejecutor":
        vueltas[t] += 1
    for campo in ("evidencia", "decisiones_tomadas", "hallazgos_no_aplicados"):
        pesado[t] += len(e.get(campo) or [])

tareas = []
for t in orden:
    roles, declarados, verificados, abiertos = {}, [], [], []
    idx_max = -1
    for (tt, r), (i, e) in ultima.items():
        if tt != t:
            continue
        est, matiz = normaliza(e.get("estado", ""))
        roles[r] = {"estado": est, **({"matiz": matiz} if matiz else {})}
        declarados += commits_de(e, ("commits",))
        verificados += commits_de(e, ALIAS_VERIFICADOS)
        if i > idx_max:
            idx_max, ult = i, e
    # sólo lo abierto en la entrada más reciente de la tarea: lo anterior quedó superado
    for a in (ult.get("abierto") or []):
        if isinstance(a, dict):
            abiertos.append({"pregunta": (a.get("pregunta") or "")[:140],
                             "riesgo": a.get("riesgo", "?")})
    decl = list(dict.fromkeys(c for c in declarados if c))
    veri = list(dict.fromkeys(c for c in verificados if c))
    tareas.append({
        "tarea": t,
        "worktree": ult.get("worktree", ""),
        "roles": roles,
        "vueltas_ejecutor": vueltas[t],
        "commits": decl,
        "commits_verificados": veri,
        "sin_verificar": [c for c in decl if c not in veri],
        "abierto": abiertos,
        "detalle_en": f"estado.sh --tarea {t}",
        "registros_historicos": pesado[t],
    })

ultimo = entradas[-1] if entradas else {}
proy = {
    "ledger": ledger,
    "entradas": len(entradas),
    "bytes_ledger": crudo,
    "situacion_actual": {
        "tarea": ultimo.get("tarea", "?"),
        "rol": ultimo.get("rol", "?"),
        "estado": normaliza(ultimo.get("estado", ""))[0],
        "siguiente_paso": (ultimo.get("siguiente_paso") or "")[:200],
    },
    "tareas": tareas,
}

if modo == "--abierto":
    proy = {"abierto": [{"tarea": t["tarea"], **a} for t in tareas for a in t["abierto"]]}
    print(json.dumps(proy, ensure_ascii=False, indent=2)); sys.exit(0)

if modo == "--json":
    print(json.dumps(proy, ensure_ascii=False, indent=2)); sys.exit(0)

# ── texto compacto (por omisión) ────────────────────────────────────────────
o = []
o.append(f"Ledger: {len(entradas)} entradas, {crudo:,} bytes. Detalle: estado.sh --tarea <T>")
s = proy["situacion_actual"]
o.append(f"Ahora: {s['tarea']} [{s['rol']}] {s['estado']}")
if s["siguiente_paso"]:
    o.append(f"Siguiente: {s['siguiente_paso']}")
o.append("")
for t in tareas:
    roles = " ".join(
        f"{r[:3]}={v['estado']}" for r, v in sorted(t["roles"].items()))
    extra = []
    if t["vueltas_ejecutor"] > 1:
        extra.append(f"{t['vueltas_ejecutor']} vueltas")
    for c in t["commits"]:
        # el sufijo ✓ separa lo confirmado por el Verificador de lo que sólo se declara
        extra.append(f"{c}✓" if c in t["commits_verificados"] else c)
    for c in t["commits_verificados"]:
        if c not in t["commits"]:
            extra.append(f"{c}✓")
    if t["abierto"]:
        extra.append(f"{len(t['abierto'])} abierto(s)")
    o.append(f"  {t['tarea']:22} {roles:52} {'  '.join(extra)}")
ab = [(t["tarea"], a) for t in tareas for a in t["abierto"]]
if ab:
    o.append("")
    o.append("Abierto:")
    for t, a in ab:
        o.append(f"  [{a['riesgo']}] {t}: {a['pregunta']}")
print("\n".join(o))
PY
