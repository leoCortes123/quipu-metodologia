#!/usr/bin/env bash
# sombra.sh — registro de discrepancias del modo sombra (Fase 2, Sistema A).
#
# En modo sombra `verificar.sh` corre ADEMÁS del protocolo completo del Verificador y no
# decide nada. Aquí se anota, tarea a tarea, si el veredicto mecánico coincidió con el del
# juez, y se calcula si ya se puede pasar el flag a vinculante.
#
# Criterio de corte (dictamen, Fase 2): 5 tareas consecutivas coincidiendo.
# Criterio de rollback: UN SOLO falso PASA —el script dice PASA y el juez rechaza por un
# hecho MECÁNICO— aborta el despliegue. Un falso FALLA es tolerable: es conservador.
#
# La distinción que más importa: si el script dice PASA y el juez rechaza por SEMÁNTICA
# (un criterio GWT incumplido), el script NO se equivocó. PASA nunca aprobó nada, sólo
# habilitaba a juzgar. Eso cuenta como coincidencia, no como falso PASA.
#
# Uso:
#   sombra.sh registrar --tarea F1/T03 --mecanico <PASA|FALLA|ruta.json> \
#                       --juez <aprobada|rechazada> [--motivo mecanico|semantico] [--nota "…"]
#   sombra.sh estado          # recuento, racha y si se puede encender el flag
#   sombra.sh estado --json
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# El ledger y las líneas base viven en el repositorio de ejecución (hermano de este).
EJEC="${QUIPU_EJECUCION:-$RAIZ/../ejecucion}"
REG="${QUIPU_SOMBRA:-$EJEC/sesiones/sombra.json}"
CMD="${1:-estado}"; shift || true

TAREA=""; MECANICO=""; JUEZ=""; MOTIVO=""; NOTA=""; FUENTE="sombra-viva"; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tarea)    TAREA="${2:-}"; shift ;;
    --mecanico) MECANICO="${2:-}"; shift ;;
    --juez)     JUEZ="${2:-}"; shift ;;
    --motivo)   MOTIVO="${2:-}"; shift ;;
    --nota)     NOTA="${2:-}"; shift ;;
    --fuente)   FUENTE="${2:-}"; shift ;;
    --json)     JSON=1 ;;
    *) echo "sombra.sh: opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

REG="$REG" CMD="$CMD" TAREA="$TAREA" MECANICO="$MECANICO" JUEZ="$JUEZ" \
MOTIVO="$MOTIVO" NOTA="$NOTA" FUENTE="$FUENTE" JSON="$JSON" python3 - <<'PY'
import json, os, sys, datetime

E = os.environ
reg = E["REG"]
UMBRAL = 5

def cargar():
    if not os.path.exists(reg):
        return []
    try:
        d = json.load(open(reg, encoding="utf-8"))
        return d if isinstance(d, list) else []
    except (json.JSONDecodeError, OSError):
        print(f"sombra.sh: registro ilegible: {reg}", file=sys.stderr)
        sys.exit(3)

def clasificar(mec, juez, motivo):
    if mec == "PASA" and juez == "aprobada":
        return "coincide"
    if mec == "FALLA" and juez == "rechazada":
        return "coincide"
    if mec == "PASA" and juez == "rechazada":
        # El script sólo habilita; si el rechazo es semántico, acertó.
        return "falso_PASA" if motivo == "mecanico" else "rechazo_semantico"
    return "falso_FALLA"          # FALLA con el juez aprobando: conservador, tolerable

entradas = cargar()

if E["CMD"] == "registrar":
    tarea, juez = E["TAREA"], E["JUEZ"].lower()
    mec = E["MECANICO"]
    if not tarea or not juez or not mec:
        print("sombra.sh registrar --tarea <T> --mecanico <PASA|FALLA|ruta.json> "
              "--juez <aprobada|rechazada> [--motivo mecanico|semantico]", file=sys.stderr)
        sys.exit(2)
    # --mecanico admite el veredicto literal o el JSON que emitió verificar.sh
    if mec not in ("PASA", "FALLA"):
        try:
            j = json.load(open(mec, encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as err:
            print(f"sombra.sh: no puedo leer el veredicto mecánico ({mec}): {err}",
                  file=sys.stderr)
            sys.exit(2)
        if j.get("modo") == "vinculante":
            print("sombra.sh: ese JSON se produjo en modo vinculante, no en sombra. "
                  "El registro de sombra sólo admite observaciones.", file=sys.stderr)
            sys.exit(2)
        mec = j.get("veredicto_mecanico", "?")
    if juez not in ("aprobada", "rechazada"):
        print("sombra.sh: --juez debe ser aprobada o rechazada", file=sys.stderr); sys.exit(2)
    motivo = E["MOTIVO"].lower() or None
    if juez == "rechazada" and motivo not in ("mecanico", "semantico"):
        print("sombra.sh: un rechazo exige --motivo mecanico|semantico. Es la distinción "
              "que decide si fue un falso PASA (rollback) o el script acertando.",
              file=sys.stderr)
        sys.exit(2)
    entrada = {
        "tarea": tarea,
        "fecha": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "mecanico": mec, "juez": juez, "motivo_rechazo": motivo,
        "clasificacion": clasificar(mec, juez, motivo),
        "fuente": E["FUENTE"],
    }
    if E["NOTA"]:
        entrada["nota"] = E["NOTA"]
    entradas.append(entrada)
    os.makedirs(os.path.dirname(reg), exist_ok=True)
    with open(reg, "w", encoding="utf-8") as fh:
        json.dump(entradas, fh, ensure_ascii=False, indent=2)
    print(json.dumps(entrada, ensure_ascii=False, indent=2))
    sys.exit(0)

if E["CMD"] != "estado":
    print(f"sombra.sh: comando desconocido: {E['CMD']} (registrar|estado)", file=sys.stderr)
    sys.exit(2)

# ── estado del despliegue ───────────────────────────────────────────────────
BUENAS = ("coincide", "rechazo_semantico")
vivas = [e for e in entradas if e.get("fuente") == "sombra-viva"]
falsos_pasa = [e for e in entradas if e.get("clasificacion") == "falso_PASA"]

racha = 0
for e in reversed(vivas):
    if e.get("clasificacion") in BUENAS:
        racha += 1
    else:
        break

if falsos_pasa:
    decision, razon = "ROLLBACK", (
        f"{len(falsos_pasa)} falso(s) PASA: el script aprobó mecánicamente algo que el juez "
        "rechazó por un hecho mecánico. El despliegue se aborta; el flag vuelve a 0.")
elif racha >= UMBRAL:
    decision, razon = "ENCENDER", (
        f"{racha}/{UMBRAL} tareas vivas consecutivas coincidiendo y ningún falso PASA. "
        "Se puede pasar QUIPU_VERIF_DETERMINISTA a 1.")
else:
    decision, razon = "SEGUIR-EN-SOMBRA", (
        f"racha {racha}/{UMBRAL} en tareas vivas. Faltan {UMBRAL - racha}.")

recuento = {}
for e in entradas:
    recuento[e.get("clasificacion", "?")] = recuento.get(e.get("clasificacion", "?"), 0) + 1

salida = {
    "registro": reg,
    "entradas": len(entradas),
    "vivas": len(vivas),
    "retrospectivas": len(entradas) - len(vivas),
    "recuento": recuento,
    "racha_viva": racha, "umbral": UMBRAL,
    "falsos_pasa": len(falsos_pasa),
    "decision": decision, "razon": razon,
}

if E["JSON"] == "1":
    print(json.dumps(salida, ensure_ascii=False, indent=2)); sys.exit(0)

print(f"Modo sombra — {len(entradas)} entradas ({len(vivas)} vivas, "
      f"{salida['retrospectivas']} retrospectivas)")
for k, v in sorted(recuento.items()):
    print(f"  {k:20} {v}")
print(f"\nRacha viva: {racha}/{UMBRAL}   Falsos PASA: {len(falsos_pasa)}")
print(f"Decisión: {decision}")
print(f"  {razon}")
if entradas:
    print("\nÚltimas:")
    for e in entradas[-6:]:
        m = f" ({e['motivo_rechazo']})" if e.get("motivo_rechazo") else ""
        print(f"  {e['tarea']:12} mec={e['mecanico']:5} juez={e['juez']}{m:12} "
              f"-> {e['clasificacion']:18} [{e.get('fuente','?')}]")
PY
