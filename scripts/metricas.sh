#!/usr/bin/env bash
# metricas.sh — línea base de consumo LLM de la flota agéntica (Sistema A).
#
# Lee la base de opencode en modo SOLO LECTURA y emite JSON por stdout con el
# consumo por sesión, agregado por agente, y el desglose de contexto por tipo
# de herramienta (el que decide el supuesto S3 del dictamen).
#
# Uso:
#   metodologia/scripts/metricas.sh                 # JSON a stdout
#   metodologia/scripts/metricas.sh --baseline      # además guarda ejecucion/sesiones/baseline-llm.json
#   QUIPU_OPENCODE_DB=/otra/ruta.db metodologia/scripts/metricas.sh
#
# Sin dependencias nuevas: bash + python3 (stdlib). No hay CLI sqlite3 en el host.
set -euo pipefail

DB="${QUIPU_OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# El ledger y las líneas base viven en el repositorio de ejecución (hermano de este).
EJEC="${QUIPU_EJECUCION:-$RAIZ/../ejecucion}"
DESTINO="$EJEC/sesiones/baseline-llm.json"
GUARDAR=0
[[ "${1:-}" == "--baseline" ]] && GUARDAR=1

if [[ ! -r "$DB" ]]; then
  echo "metricas.sh: no puedo leer la base de opencode: $DB" >&2
  exit 2
fi

SALIDA="$(QUIPU_DB="$DB" python3 - <<'PY'
import sqlite3, json, os, collections, datetime

DB = os.environ["QUIPU_DB"]
# immutable=1: garantiza que jamás se escribe ni se crea -wal/-shm sobre la base viva.
con = sqlite3.connect(f"file:{DB}?mode=ro&immutable=1", uri=True)
q = lambda sql, *a: con.execute(sql, a).fetchall()

# Estimador de tokens a partir de caracteres. La base no guarda tokens por
# herramienta, sólo por paso; 4 chars/token es la aproximación estándar y se
# calibra más abajo contra el crecimiento real de contexto observado.
CHARS_POR_TOKEN = 4.0
tok = lambda n: round(n / CHARS_POR_TOKEN)

# Los tres roles de la flota (Sistema A). El resto de agentes que aparecen en la
# base son los genéricos de opencode (build/plan/explore/…), que NO son la flota.
FLOTA = ("orquestador", "ejecutor", "verificador")

# ── sesiones ────────────────────────────────────────────────────────────────
sesiones, por_agente = [], collections.defaultdict(lambda: collections.Counter())
agente_de = {}
for (sid, slug, agente, modelo, ti, to, tcr, tcw, coste, tc, tu) in q("""
    select id, slug, coalesce(agent,'?'), coalesce(model,''),
           tokens_input, tokens_output, tokens_cache_read, tokens_cache_write,
           cost, time_created, time_updated
      from session"""):
    agente_de[sid] = agente
    try:
        modelo_id = json.loads(modelo).get("id", "") if modelo else ""
    except Exception:
        modelo_id = modelo
    turnos = q("""select count(*) from message
                   where session_id = ?
                     and json_extract(data,'$.role') = 'assistant'""", sid)[0][0]
    contexto = ti + tcr                      # todo lo que entró al modelo
    sesiones.append({
        "sesion": sid, "slug": slug, "agente": agente, "modelo": modelo_id,
        "tokens_input": ti, "tokens_output": to,
        "tokens_cache_read": tcr, "tokens_cache_write": tcw,
        "contexto_total": contexto,
        "turnos_asistente": turnos,
        "duracion_s": round((tu - tc) / 1000),
        # tasa K/C = fracción del contexto servida desde caché (cache_read/contexto).
        "tasa_kc": round(tcr / contexto, 4) if contexto else 0.0,
        "coste_usd": round(coste, 6),
        "tokens_por_turno": round(contexto / turnos) if turnos else 0,
        "_tc": tc, "_tu": tu,
    })
    a = por_agente[agente]
    for k, v in (("sesiones",1), ("tokens_input",ti), ("tokens_output",to),
                 ("tokens_cache_read",tcr), ("tokens_cache_write",tcw),
                 ("turnos_asistente",turnos), ("duracion_s",round((tu-tc)/1000))):
        a[k] += v
    a["coste_usd"] += coste

sesiones.sort(key=lambda s: -s["contexto_total"])
iso = lambda ms: datetime.datetime.fromtimestamp(ms / 1000).astimezone().isoformat(timespec="seconds")
ctx_total = sum(s["contexto_total"] for s in sesiones)
ctx_flota = sum(s["contexto_total"] for s in sesiones if s["agente"] in FLOTA)

agentes = {}
for nombre, a in sorted(por_agente.items()):
    ctx = a["tokens_input"] + a["tokens_cache_read"]
    agentes[nombre] = {
        "sesiones": a["sesiones"],
        "tokens_input": a["tokens_input"], "tokens_output": a["tokens_output"],
        "tokens_cache_read": a["tokens_cache_read"],
        "tokens_cache_write": a["tokens_cache_write"],
        "contexto_total": ctx,
        "turnos_asistente": a["turnos_asistente"],
        "duracion_s": a["duracion_s"],
        "tasa_kc": round(a["tokens_cache_read"] / ctx, 4) if ctx else 0.0,
        "coste_usd": round(a["coste_usd"], 6),
        "tokens_por_turno": round(ctx / a["turnos_asistente"]) if a["turnos_asistente"] else 0,
    }

# ── pasos por sesión: para el peso de reenvío ───────────────────────────────
# Una salida de herramienta emitida en el turno k se reenvía íntegra en cada
# turno posterior de la misma sesión. El coste real de contexto no es su tamaño,
# es tamaño x turnos restantes. Ése es el número que hay que optimizar.
pasos = collections.defaultdict(list)
for sid, t in q("""select session_id, time_created from part
                    where json_extract(data,'$.type') = 'step-finish'"""):
    pasos[sid].append(t)

# ── desglose por tipo de herramienta ────────────────────────────────────────
bruto      = collections.Counter()   # chars emitidos una vez
reenviado  = collections.Counter()   # chars x turnos posteriores
llamadas   = collections.Counter()
por_rol    = collections.defaultdict(lambda: collections.Counter())
por_rol_re = collections.defaultdict(lambda: collections.Counter())
archivos   = collections.Counter()
comandos   = collections.Counter()
ci_verificador = 0

# Subclasificación de bash: es la que responde a S3 en sentido estricto.
def clase_bash(cmd: str) -> str:
    c = cmd.lower()
    if "composer ci" in c or "pnpm run ci" in c or "pest" in c or "phpstan" in c or "pint" in c or "vitest" in c:
        return "bash:ci"
    if "git diff" in c or "git show" in c or "git log" in c:
        return "bash:diff"
    return "bash:otros"

for sid, tc, data in q("""select session_id, time_created, data from part
                           where json_extract(data,'$.type') = 'tool'"""):
    j = json.loads(data)
    est = j.get("state", {})
    salida = est.get("output") or est.get("error") or ""
    n = len(salida)
    posteriores = sum(1 for t in pasos.get(sid, []) if t > tc)
    herramienta = j.get("tool", "?")
    entrada = est.get("input") or {}
    etiqueta = clase_bash(entrada.get("command", "")) if herramienta == "bash" else herramienta
    rol = agente_de.get(sid, "?")

    if etiqueta == "bash:ci" and rol == "verificador":
        ci_verificador += 1
    llamadas[etiqueta] += 1
    bruto[etiqueta] += n
    reenviado[etiqueta] += n * posteriores
    por_rol[rol][etiqueta] += n
    por_rol_re[rol][etiqueta] += n * posteriores
    if herramienta == "read":
        archivos[entrada.get("filePath", "?")] += n
    if herramienta == "bash":
        comandos[entrada.get("command", "")[:120].replace("\n", " ")] += n

tot_bruto, tot_re = sum(bruto.values()), sum(reenviado.values())

def tabla(cnt_bruto, cnt_re, cnt_llamadas=None):
    tb, tr = sum(cnt_bruto.values()), sum(cnt_re.values())
    filas = []
    for k, v in sorted(cnt_re.items(), key=lambda x: -x[1]):
        filas.append({
            "herramienta": k,
            "llamadas": cnt_llamadas[k] if cnt_llamadas else None,
            "chars_bruto": cnt_bruto[k], "tokens_bruto": tok(cnt_bruto[k]),
            "pct_bruto": round(100 * cnt_bruto[k] / tb, 2) if tb else 0.0,
            "tokens_reenviados": tok(cnt_re[k]),
            "pct_reenviado": round(100 * v / tr, 2) if tr else 0.0,
        })
    return filas

# ── calibración del estimador chars/4 ───────────────────────────────────────
# Cruce contra el crecimiento real de contexto entre pasos consecutivos: si el
# estimador estuviera muy desviado, el desglose de arriba no sería defendible.
crec = 0
for sid in pasos:
    ins = [json.loads(d)["tokens"]["input"] + json.loads(d)["tokens"]["cache"]["read"]
           for (d,) in q("""select data from part
                             where session_id = ?
                               and json_extract(data,'$.type')='step-finish'
                             order by time_created""", sid)]
    crec += sum(max(0, b - a) for a, b in zip(ins, ins[1:]))

# ── veredicto S3 ────────────────────────────────────────────────────────────
# S3 (dictamen): "el grueso del contexto del verificador es salida de CI y diffs".
ci_diff_global = tok(reenviado["bash:ci"] + reenviado["bash:diff"])
v = por_rol_re.get("verificador", collections.Counter())
v_tot = sum(v.values())
v_ci_diff = v["bash:ci"] + v["bash:diff"]
v_read = v["read"]
s3 = {
    "supuesto": "S3: el grueso del contexto del verificador es salida de CI y diffs",
    "pct_ci_diff_en_verificador": round(100 * v_ci_diff / v_tot, 2) if v_tot else 0.0,
    "pct_read_en_verificador": round(100 * v_read / v_tot, 2) if v_tot else 0.0,
    "pct_ci_diff_global": round(100 * (reenviado["bash:ci"] + reenviado["bash:diff"]) / tot_re, 2) if tot_re else 0.0,
    "sesiones_verificador": agentes.get("verificador", {}).get("sesiones", 0),
    "ejecuciones_ci_por_el_verificador": ci_verificador,
    "veredicto": None, "lectura": None,
}
s3["veredicto"] = "CONFIRMADO" if s3["pct_ci_diff_en_verificador"] >= 50 else "REFUTADO"
s3["lectura"] = (
    f"CI+diff aportan {s3['pct_ci_diff_en_verificador']}% del contexto reenviado del "
    f"verificador; las lecturas de archivo aportan {s3['pct_read_en_verificador']}%."
)

print(json.dumps({
    "generado": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "base": DB,
    "estimador": {"chars_por_token": CHARS_POR_TOKEN,
                  "nota": "la base no guarda tokens por herramienta; se estiman por caracteres"},
    "total": {
        "sesiones": len(sesiones),
        "tokens_input": sum(s["tokens_input"] for s in sesiones),
        "tokens_output": sum(s["tokens_output"] for s in sesiones),
        "tokens_cache_read": sum(s["tokens_cache_read"] for s in sesiones),
        "tokens_cache_write": sum(s["tokens_cache_write"] for s in sesiones),
        "contexto_total": sum(s["contexto_total"] for s in sesiones),
        "turnos_asistente": sum(s["turnos_asistente"] for s in sesiones),
        "coste_usd": round(sum(s["coste_usd"] for s in sesiones), 6),
        "tasa_kc": round(sum(s["tokens_cache_read"] for s in sesiones) /
                         sum(s["contexto_total"] for s in sesiones), 4),
        "ratio_entrada_salida": round(sum(s["contexto_total"] for s in sesiones) /
                                      sum(s["tokens_output"] for s in sesiones), 1),
    },
    "cobertura_flota": {
        "roles": list(FLOTA),
        "sesiones_flota": sum(1 for s in sesiones if s["agente"] in FLOTA),
        "sesiones_no_flota": sum(1 for s in sesiones if s["agente"] not in FLOTA),
        "contexto_flota": ctx_flota,
        "contexto_no_flota": ctx_total - ctx_flota,
        "pct_contexto_flota": round(100 * ctx_flota / ctx_total, 2) if ctx_total else 0.0,
        "ventana": {"desde": iso(min(s["_tc"] for s in sesiones)),
                    "hasta": iso(max(s["_tu"] for s in sesiones))},
        "nota": "la base de opencode sólo cubre las sesiones que corrieron EN opencode; "
                "si la flota se portó a otro runtime, su consumo posterior no está aquí",
    },
    "por_agente": agentes,
    "sesiones": [{k: v for k, v in s.items() if not k.startswith("_")} for s in sesiones],
    "herramientas_global": tabla(bruto, reenviado, llamadas),
    "herramientas_por_rol": {
        rol: tabla(por_rol[rol], por_rol_re[rol])
        for rol in ("orquestador", "ejecutor", "verificador") if rol in por_rol
    },
    "top_archivos_leidos": [{"archivo": f, "chars": n, "tokens": tok(n)}
                            for f, n in archivos.most_common(15)],
    "top_comandos_bash": [{"comando": c, "chars": n, "tokens": tok(n)}
                          for c, n in comandos.most_common(10)],
    "calibracion": {
        "tokens_estimados_salida_herramientas": tok(tot_bruto),
        "crecimiento_real_de_contexto_entre_pasos": crec,
        "nota": "el primero debe ser una fracción coherente del segundo; el resto es "
                "prompt de sistema, instrucciones de agente, texto y razonamiento",
    },
    "s3": s3,
}, indent=2, ensure_ascii=False))
PY
)"

printf '%s\n' "$SALIDA"

if [[ $GUARDAR -eq 1 ]]; then
  mkdir -p "$EJEC/sesiones"
  printf '%s\n' "$SALIDA" > "$DESTINO"
  echo "metricas.sh: línea base guardada en $DESTINO" >&2
fi
