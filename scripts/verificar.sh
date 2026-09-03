#!/usr/bin/env bash
# verificar.sh — pasos MECÁNICOS del protocolo del Verificador (Sistema A).
#
# Ejecuta los pasos 1, 3, 4 y 5 de `metodologia/agents/verificador.md` —parsear la tarea,
# CI completo, regla suite-diff, alcance tocado vs. declarado, commits con mensaje
# literal— y emite un JSON. NO ejecuta el paso 2 (juzgar los criterios GWT): eso sigue
# siendo del modelo, y este script no lo sustituye.
#
#   FALLA es vinculante: si sale FALLA, la tarea está rechazada y no hay nada que juzgar.
#   PASA NO APRUEBA NADA: sólo habilita al Verificador a entrar a juzgar semántica.
#
# Así la regla 14 de CONSTITUCION.md (quien implementó nunca verifica) y el Default-FAIL
# quedan intactos: el script no aprueba, sólo descarta.
#
# Uso:
#   QUIPU_VERIF_DETERMINISTA=1 metodologia/scripts/verificar.sh <ruta-tarea> <worktree> [opciones]
#     --sin-ci            omite CI y suite-diff (sólo comprobaciones git: alcance y commits)
#     --fijar-baseline    registra el conteo de suites de esta corrida como baseline
#     --log <ruta>        destino del log completo (por omisión /tmp/verif-<tarea>.log)
#     --base <sha>        base explícita en vez del merge-base con main (replay histórico)
#     --checkpoint <f>    ledger de checkpoints (por omisión ejecucion/sesiones/progress.json)
#
# TRAMPA CONOCIDA (metodologia/SESION-EJECUCION.md): la pila Docker es exclusiva y monta ./code
# relativo al directorio de invocación. Este script levanta la pila DESDE la worktree,
# lo que sustituye la del repo principal mientras corre. Dos verificaciones no pueden
# correr a la vez. El CI tarda más que el techo de 10 min de una invocación de shell:
# lánzalo en segundo plano y lee el JSON al terminar.
#
# Sin dependencias nuevas: bash + git + docker compose + python3 de la stdlib.
set -uo pipefail

# El flag tiene TRES estados, no dos (Fase 2 del dictamen: sombra antes que vinculante).
#   0       apagado (por omisión): el script no corre; el Verificador trabaja a mano.
#   sombra  el script corre y observa, pero NO decide: el Verificador hace además el
#           protocolo completo y se registra la discrepancia (metodologia/scripts/sombra.sh).
#   1       vinculante: FALLA rechaza la tarea sin más. Sólo tras 5/5 en sombra.
case "${QUIPU_VERIF_DETERMINISTA:-0}" in
  sombra) VINCULANTE=0; MODO="sombra" ;;
  1)      VINCULANTE=1; MODO="vinculante" ;;
  0|"")
    echo "verificar.sh: QUIPU_VERIF_DETERMINISTA=0 (por omisión). La verificación" >&2
    echo "  determinista está apagada; el Verificador hace los pasos a mano como siempre." >&2
    echo "  Modo sombra (observa, no decide): QUIPU_VERIF_DETERMINISTA=sombra" >&2
    echo "  Vinculante: QUIPU_VERIF_DETERMINISTA=1 — sólo tras 5/5 (sombra.sh estado)" >&2
    exit 3 ;;
  *)
    echo "verificar.sh: QUIPU_VERIF_DETERMINISTA='${QUIPU_VERIF_DETERMINISTA}' no es un" >&2
    echo "  valor válido. Usa 0 (apagado), sombra (observa) o 1 (vinculante)." >&2
    exit 2 ;;
esac

TAREA_MD="${1:-}"; WT="${2:-}"; shift 2 2>/dev/null || true
SIN_CI=0; FIJAR=0; LOG=""; BASE_FIJA=""; CKPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sin-ci)         SIN_CI=1 ;;
    --fijar-baseline) FIJAR=1 ;;
    --log)            LOG="${2:-}"; shift ;;
    --base)           BASE_FIJA="${2:-}"; shift ;;   # base explícita (replay histórico)
    --checkpoint)     CKPT="${2:-}"; shift ;;
    *) echo "verificar.sh: opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ -z "$TAREA_MD" || -z "$WT" ]]; then
  echo "verificar.sh <ruta-tarea> <worktree> [--sin-ci] [--fijar-baseline] [--log ruta]" >&2
  exit 2
fi
[[ -r "$TAREA_MD" ]] || { echo "verificar.sh: no puedo leer la tarea: $TAREA_MD" >&2; exit 2; }
[[ -d "$WT/.git" || -f "$WT/.git" ]] || { echo "verificar.sh: no es una worktree git: $WT" >&2; exit 2; }

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# El ledger y las líneas base viven en el repositorio de ejecución (hermano de este).
EJEC="${QUIPU_EJECUCION:-$RAIZ/../ejecucion}"
TAREA_ID="$(python3 -c "
import re,sys,os
p=os.path.abspath(sys.argv[1]); m=re.search(r'/TAREAS/(F\d+)/(T\d+)',p)
print(f'{m.group(1)}/{m.group(2)}' if m else os.path.basename(p).rsplit('.',1)[0])" "$TAREA_MD")"
SLUG="$(echo "$TAREA_ID" | tr 'A-Z/' 'a-z-')"
LOG="${LOG:-/tmp/verif-${SLUG}.log}"
: > "$LOG"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── git: base, cabeza, alcance, commits ─────────────────────────────────────
BASE="${BASE_FIJA:-$(git -C "$WT" merge-base main HEAD 2>/dev/null || echo "")}"
HEAD_SHA="$(git -C "$WT" rev-parse --short HEAD 2>/dev/null || echo "")"
{
  echo "### verificar.sh — $TAREA_ID"
  echo "### worktree: $WT"
  echo "### base: ${BASE:-<sin merge-base con main>}  head: $HEAD_SHA"
  echo
} >> "$LOG"

if [[ -n "$BASE" ]]; then
  git -C "$WT" diff --name-only "$BASE"..HEAD > "$TMP/tocado.txt" 2>>"$LOG" || : > "$TMP/tocado.txt"
  git -C "$WT" log --format='%h%x1f%B%x1e' "$BASE"..HEAD > "$TMP/commits.txt" 2>>"$LOG" || : > "$TMP/commits.txt"
else
  : > "$TMP/tocado.txt"; : > "$TMP/commits.txt"
fi
git -C "$WT" status --porcelain > "$TMP/status.txt" 2>>"$LOG" || : > "$TMP/status.txt"

# ── CI dentro de los contenedores, nunca el php/pnpm del host ───────────────
CI_API_EXIT="null"; CI_WEB_EXIT="null"
if [[ $SIN_CI -eq 0 ]]; then
  {
    echo "### docker compose up -d (desde $WT — sustituye la pila del repo principal)"
  } >> "$LOG"
  ( cd "$WT" && docker compose up -d ) >> "$LOG" 2>&1
  echo "### composer ci" >> "$LOG"
  ( cd "$WT" && docker compose exec -T -e COMPOSER_PROCESS_TIMEOUT=1800 api composer ci ) \
      > "$TMP/ci_api.txt" 2>&1
  CI_API_EXIT=$?
  cat "$TMP/ci_api.txt" >> "$LOG"
  echo "### pnpm run ci" >> "$LOG"
  ( cd "$WT" && docker compose exec -T web pnpm run ci ) > "$TMP/ci_web.txt" 2>&1
  CI_WEB_EXIT=$?
  cat "$TMP/ci_web.txt" >> "$LOG"
else
  : > "$TMP/ci_api.txt"; : > "$TMP/ci_web.txt"
  echo "### CI omitido (--sin-ci)" >> "$LOG"
fi

# ── ensamblado del veredicto ────────────────────────────────────────────────
TAREA_MD="$TAREA_MD" TAREA_ID="$TAREA_ID" WT="$WT" TMP="$TMP" LOG="$LOG" \
CI_API_EXIT="$CI_API_EXIT" CI_WEB_EXIT="$CI_WEB_EXIT" SIN_CI="$SIN_CI" \
FIJAR="$FIJAR" BASELINE="$EJEC/sesiones/baseline-suites.json" \
MODO="$MODO" VINCULANTE="$VINCULANTE" \
CKPT="${CKPT:-$EJEC/sesiones/progress.json}" \
BASE="$BASE" HEAD_SHA="$HEAD_SHA" python3 - <<'PY'
import json, os, re, sys

E = os.environ
tmp, sin_ci = E["TMP"], E["SIN_CI"] == "1"
leer = lambda n: open(os.path.join(tmp, n), encoding="utf-8", errors="replace").read()
tarea_md = open(E["TAREA_MD"], encoding="utf-8").read()

fallos = []
# Primeras líneas del error + código de salida, SIEMPRE: el agente tiene que poder
# actuar sin abrir el log.
def cabeza(texto, n=12):
    utiles = [l.rstrip() for l in texto.splitlines() if l.strip()]
    return utiles[-n:] if utiles else []

# ── CI ──────────────────────────────────────────────────────────────────────
def lee_ci_api(salida, code):
    d = {"exit": code}
    if sin_ci:
        return {"exit": None, "omitido": True}
    d["pint"]    = "ok" if re.search(r"PASS.*?\d+ files", salida) else "falla"
    d["phpstan"] = "ok" if "[OK] No errors" in salida else "falla"
    m = re.search(r"Tests:\s+(.+)", salida)
    d["pest"] = m.group(1).strip() if m else "sin resumen"
    m = re.search(r"Duration:\s+(.+)", salida)
    if m:
        d["duracion"] = m.group(1).strip()
    return d

api_txt, web_txt = leer("ci_api.txt"), leer("ci_web.txt")
api_exit = None if E["CI_API_EXIT"] == "null" else int(E["CI_API_EXIT"])
web_exit = None if E["CI_WEB_EXIT"] == "null" else int(E["CI_WEB_EXIT"])

ci_api = lee_ci_api(api_txt, api_exit)
ci_web = {"exit": None, "omitido": True} if sin_ci else {"exit": web_exit}

if not sin_ci:
    if api_exit != 0:
        fallos.append({"comprobacion": "ci_api", "exit": api_exit,
                       "error": cabeza(api_txt)})
    if web_exit != 0:
        fallos.append({"comprobacion": "ci_web", "exit": web_exit,
                       "error": cabeza(web_txt)})

# ── regla suite-diff ────────────────────────────────────────────────────────
# CONSTITUCION regla 10: un CI verde con suites desactivadas o saltadas no vale.
# Vigilamos tres cosas: tests que fallan, tests saltados, y caída del total contra
# el baseline registrado.
def conteos(salida):
    d = {}
    m = re.search(r"Tests:\s+(.+)", salida)
    if m:
        for n, etiqueta in re.findall(r"(\d+)\s+(passed|failed|skipped|incomplete|todo|risky)",
                                      m.group(1)):
            d[etiqueta] = int(n)
    return d

suite = {"regresiones": []}
if sin_ci:
    suite = {"regresiones": [], "omitido": True}
else:
    c = conteos(api_txt)
    suite["conteos"] = c
    for etiqueta in ("failed", "skipped", "incomplete", "risky"):
        if c.get(etiqueta):
            suite["regresiones"].append(f"{c[etiqueta]} {etiqueta}")
    ruta_base = E["BASELINE"]
    base_prev = None
    if os.path.exists(ruta_base):
        try:
            base_prev = json.load(open(ruta_base, encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            base_prev = None
    if base_prev is None:
        suite["baseline"] = "ausente"
        fallos.append({"comprobacion": "suite_diff", "exit": None,
                       "error": [f"sin baseline en {ruta_base}: la regla suite-diff no es "
                                 "verificable. Fíjalo con --fijar-baseline sobre un árbol "
                                 "aprobado (Default-FAIL: sin baseline no se pasa)."]})
    else:
        antes, ahora = base_prev.get("passed", 0), c.get("passed", 0)
        suite["baseline"] = {"passed": antes, "commit": base_prev.get("commit", "?")}
        if ahora < antes:
            suite["regresiones"].append(f"passed cayó de {antes} a {ahora}")
    if suite["regresiones"]:
        fallos.append({"comprobacion": "suite_diff", "exit": None,
                       "error": suite["regresiones"]})
    if E["FIJAR"] == "1" and api_exit == 0:
        os.makedirs(os.path.dirname(ruta_base), exist_ok=True)
        with open(ruta_base, "w", encoding="utf-8") as fh:
            json.dump({"passed": c.get("passed", 0), "commit": E["HEAD_SHA"],
                       "tarea": E["TAREA_ID"]}, fh, ensure_ascii=False, indent=2)
        suite["baseline_fijado"] = c.get("passed", 0)

# ── alcance: tocado vs. declarado ───────────────────────────────────────────
# El archivo de tarea no trae una lista mecánica; declara los archivos en prosa,
# entre comillas invertidas. Extraemos de ahí lo que parezca ruta o nombre de archivo.
declarado = sorted({
    t.strip() for t in re.findall(r"`([^`\n]+)`", tarea_md)
    if ("/" in t or re.search(r"\.\w{2,4}$", t.strip())) and " " not in t.strip()
})
bases_declaradas = {os.path.basename(d) for d in declarado}

tocado = [l for l in leer("tocado.txt").splitlines() if l.strip()]
# Un archivo sin commitear es, por definición, alcance no declarado (VALIDACION.md 5).
sucio = [l[3:].strip() for l in leer("status.txt").splitlines() if l.strip()]

def en_alcance(ruta):
    b = os.path.basename(ruta)
    return b in bases_declaradas or any(d in ruta or ruta in d for d in declarado)

# El paso 1 del protocolo manda leer también el checkpoint, y con razón: el alcance de
# una tarea sólo lo ensancha una resolución de ESCALAMIENTO firmada por el humano
# (F0/T01 es el precedente: reformatear un .json fuera de la tarea, aprobado por el
# propietario). Que el Ejecutor se autodeclare el archivo en `archivos_tocados` NO
# autoriza nada; tiene que estar nombrado en la resolución.
resoluciones = []
try:
    with open(E["CKPT"], encoding="utf-8") as fh:
        for entrada in json.load(fh):
            if not isinstance(entrada, dict) or entrada.get("tarea") != E["TAREA_ID"]:
                continue
            for clave, valor in entrada.items():
                if clave.startswith("resolucion"):
                    resoluciones.append(json.dumps(valor, ensure_ascii=False))
except (OSError, json.JSONDecodeError, TypeError):
    pass
texto_resoluciones = " ".join(resoluciones)

autorizado, fuera = [], []
for r in tocado:
    if en_alcance(r):
        continue
    if os.path.basename(r) in texto_resoluciones:
        autorizado.append(r)
    else:
        fuera.append(r)

alcance = {"declarado": declarado, "tocado": tocado, "fuera": fuera,
           "autorizado_por_escalamiento": autorizado, "sin_commitear": sucio}
if autorizado:
    alcance["resoluciones_citadas"] = [t[:200] for t in resoluciones]
if fuera:
    fallos.append({"comprobacion": "alcance", "exit": None,
                   "error": [f"archivo tocado fuera del alcance declarado: {r}" for r in fuera]})
if sucio:
    fallos.append({"comprobacion": "alcance", "exit": None,
                   "error": [f"árbol sucio, sin commitear: {r}" for r in sucio]})

# ── commits con mensaje literal ─────────────────────────────────────────────
# El mensaje esperado va en un bloque cercado justo tras una línea con "Commit".
import textwrap
esperados = []
# La valla puede ir indentada dentro de una lista numerada (así lo hace toda F0),
# así que se admite sangría y se le quita antes de comparar.
for m in re.finditer(r"Commit[^\n]*:?[ \t]*\n+[ \t]*```[a-z]*\n(.*?)\n[ \t]*```",
                     tarea_md, re.S):
    esperados.append(textwrap.dedent(m.group(1)).strip())

reales = []
for reg in leer("commits.txt").split("\x1e"):
    if "\x1f" in reg:
        sha, cuerpo = reg.split("\x1f", 1)
        reales.append({"sha": sha.strip(), "mensaje": cuerpo.strip()})

# Los trailers (Co-Authored-By, Claude-Session, Signed-off-by…) los añade el entorno,
# no la tarea: "mensaje literal" significa el cuerpo especificado intacto, sin ellos.
TRAILER = re.compile(r"^[A-Z][A-Za-z]*(?:-[A-Za-z]+)*: .+$")

def sin_trailers(mensaje):
    parrafos = re.split(r"\n\s*\n", (mensaje or "").strip())
    while len(parrafos) > 1:
        lineas = [l for l in parrafos[-1].splitlines() if l.strip()]
        if lineas and all(TRAILER.match(l.strip()) for l in lineas):
            parrafos.pop()
        else:
            break
    return "\n\n".join(parrafos)

norma = lambda s: re.sub(r"\s+", " ", sin_trailers(s)).strip().lower()

commits = []
for c in reales:
    coincide = any(norma(c["mensaje"]) == norma(e) for e in esperados) if esperados else None
    commits.append({"sha": c["sha"], "mensaje_coincide": coincide,
                    "asunto": c["mensaje"].splitlines()[0][:100] if c["mensaje"] else ""})

if esperados and not reales:
    fallos.append({"comprobacion": "commits", "exit": None,
                   "error": ["la tarea especifica un mensaje de commit y no hay ningún "
                             f"commit en {E['BASE'][:9]}..{E['HEAD_SHA']}"]})
elif esperados and not any(c["mensaje_coincide"] for c in commits):
    fallos.append({"comprobacion": "commits", "exit": None,
                   "error": ["ningún commit coincide literalmente con el mensaje especificado",
                             "esperado: " + norma(esperados[0])[:160],
                             "encontrado: " + ", ".join(norma(c["asunto"])[:80] for c in commits)]})

print(json.dumps({
    "tarea": E["TAREA_ID"],
    "worktree": E["WT"],
    "base": E["BASE"], "head": E["HEAD_SHA"],
    "ci_api": ci_api,
    "ci_web": ci_web,
    "suite_diff": suite,
    "alcance": alcance,
    "commits": commits,
    "modo": E["MODO"],
    "vinculante": E["VINCULANTE"] == "1",
    "veredicto_mecanico": "FALLA" if fallos else "PASA",
    "fallos": fallos,
    "log_completo": E["LOG"],
    "nota": ("MODO SOMBRA: este veredicto NO decide nada. Haz el protocolo completo igual "
             "y registra la discrepancia con metodologia/scripts/sombra.sh registrar. "
             "El script observa; el que verifica sigues siendo tú."
             if E["MODO"] == "sombra" else
             "FALLA es vinculante. PASA no aprueba: sólo habilita el paso 2 (criterios GWT), "
             "que juzga el Verificador. Este script nunca juzga semántica."),
}, ensure_ascii=False, indent=2))
PY
