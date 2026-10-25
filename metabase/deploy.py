"""Deploy metabase/metabase.yml (models, metrics, dashboards) through the Metabase REST API.

Idempotent: everything is matched by name inside the project collection and updated in place.

    MB_URL=http://localhost:3000 MB_API_KEY=... MB_DATABASE="Retail warehouse" python metabase/deploy.py
    python metabase/deploy.py --plan plan.json    # resolved payloads with {{model:…}} / {{metric:…}} placeholders
"""

import argparse
import copy
import json
import os
import pathlib
import re
import sys

import jinja2
import requests
import yaml
from dotenv import load_dotenv

SPEC = pathlib.Path(__file__).with_name("metabase.yml")
BASE = {"BigInteger": "type/BigInteger", "Integer": "type/Integer", "Decimal": "type/Decimal",
        "Date": "type/Date", "Text": "type/Text", "Boolean": "type/Boolean"}
SEMANTIC = {"PK": "type/PK", "FK": "type/FK", "Category": "type/Category", "Country": "type/Country",
            "Currency": "type/Currency", "Quantity": "type/Quantity", "Score": "type/Score"}
USD = {"currency": "USD", "number_style": "currency", "currency_style": "symbol"}
HEATMAP_COLORS = ["#F2F6FB", "#2F6FAD"]


def field_ref(token, columns):
    """'@col' or '@col|month' → an MBQL field ref typed from the model's column list."""
    name, _, unit = token[1:].partition("|")
    if name not in columns:
        sys.exit(f"unknown column {name!r}")
    opts = {"base-type": BASE[columns[name]["type"]]}
    if unit:
        opts["temporal-unit"] = unit
    return ["field", name, opts]


def expand(node, columns):
    if isinstance(node, str):
        if node.startswith("@"):
            return field_ref(node, columns)
        if node.startswith("metric:"):
            return ["metric", "{{metric:%s}}" % node[7:]]
        return node
    if isinstance(node, list):
        return [expand(x, columns) for x in node]
    if isinstance(node, dict):
        return {k: expand(v, columns) for k, v in node.items()}
    return node


def mbql_query(model, query, columns):
    q = {"source-table": "card__{{model:%s}}" % model}
    q.update({key: expand(value, columns) for key, value in query.items()})
    return q


def build_plan(spec, database_id):
    models = {m["name"]: m for m in spec["models"]}
    plan = {"collection": spec["collection"], "models": [], "metrics": [], "cards": [], "dashboards": []}

    for m in spec["models"]:
        plan["models"].append({
            "name": m["name"], "type": "model", "display": "table", "description": m.get("description"),
            "visualization_settings": {},
            "dataset_query": {"database": database_id, "type": "native", "native": {"query": m["sql"].strip()}},
            "columns": {
                name: {"display_name": c["name"], "semantic_type": SEMANTIC.get(c.get("semantic")),
                       "settings": {**(USD if c.get("semantic") == "Currency" else {}), **c.get("settings", {})} or None}
                for name, c in m["columns"].items()
            },
        })

    for metric in spec["metrics"]:
        cols = models[metric["model"]]["columns"]
        agg = expand(metric["aggregation"], cols)
        plan["metrics"].append({
            "name": metric["name"], "type": "metric", "display": "scalar", "description": metric.get("description"),
            "visualization_settings": {},
            "dataset_query": {"database": database_id, "type": "query",
                              "query": {"source-table": "card__{{model:%s}}" % metric["model"],
                                        "aggregation": [["aggregation-options", agg, {"name": metric["name"], "display-name": metric["name"]}]]}},
        })

    env = jinja2.Environment()
    for dash in spec["dashboards"]:
        params = []
        for p in dash.get("parameters", []):
            params.append({"id": p["slug"], "name": p["name"], "slug": p["slug"], "type": p["type"],
                           "sectionId": "date" if p["type"].startswith("date") else "string",
                           "_field": p["field"], "_model": p.get("model", "Orders")})
        dashcards = []
        for card in dash["cards"]:
            col, row, w, h = card["layout"]
            dc = {"col": col, "row": row, "size_x": w, "size_y": h, "card_name": card.get("name"),
                  "parameter_mappings": [], "visualization_settings": {}}
            if "text" in card:
                dc.update(card_name=None, visualization_settings={"text": card["text"].strip(), "virtual_card": {
                    "name": None, "display": "text", "visualization_settings": {}, "dataset_query": {}, "archived": False}})
                dashcards.append(dc)
                continue

            viz = copy.deepcopy(card.get("viz") or {})
            if card.get("heatmap_columns"):
                viz["table.column_formatting"] = [{"columns": card["heatmap_columns"], "type": "range",
                                                   "colors": HEATMAP_COLORS, "min_type": None, "max_type": None,
                                                   "highlight_row": False}]
            if "sql" in card:
                dataset_query = {"database": database_id, "type": "native",
                                 "native": {"query": env.from_string(card["sql"]).render().strip(), "template-tags": {}}}
                source_model = None
            else:
                source_model = card["source"].split(":", 1)[1]
                cols = models[source_model]["columns"]
                dataset_query = {"database": database_id, "type": "query",
                                 "query": mbql_query(source_model, card["query"], cols)}
                for p in params:
                    if p["_model"] == source_model:
                        dc["parameter_mappings"].append({
                            "parameter_id": p["id"],
                            "target": ["dimension", field_ref("@" + p["_field"], cols), {"stage-number": 0}]})
            if card.get("click"):
                pid = card["click"]["crossfilter"]
                column = card["click"]["column"]
                dc["visualization_settings"]["click_behavior"] = {"type": "crossfilter", "parameterMapping": {
                    pid: {"id": pid, "source": {"type": "column", "id": column, "name": column},
                          "target": {"type": "parameter", "id": pid}}}}
            plan["cards"].append({"name": card["name"], "type": "question", "display": card["display"],
                                  "description": card.get("description"), "visualization_settings": viz,
                                  "dataset_query": dataset_query})
            dashcards.append(dc)
        plan["dashboards"].append({"name": dash["name"], "description": dash.get("description"),
                                   "parameters": [{k: v for k, v in p.items() if not k.startswith("_")} for p in params],
                                   "dashcards": dashcards})
    return plan


def resolve(node, ids):
    """Replace {{model:Name}} / {{metric:Name}} placeholders with real card ids."""
    if isinstance(node, str):
        m = re.fullmatch(r"(card__)?\{\{(model|metric):(.+)\}\}", node)
        if m:
            cid = ids[(m.group(2), m.group(3))]
            return f"card__{cid}" if m.group(1) else cid
        return node
    if isinstance(node, list):
        return [resolve(x, ids) for x in node]
    if isinstance(node, dict):
        return {k: resolve(v, ids) for k, v in node.items()}
    return node


class Metabase:
    def __init__(self, url, api_key):
        self.url = url.rstrip("/")
        self.s = requests.Session()
        self.s.headers["x-api-key"] = api_key

    def __call__(self, method, path, body=None):
        r = self.s.request(method, f"{self.url}/api{path}", json=body, timeout=120)
        if r.status_code >= 400:
            sys.exit(f"{method} {path} failed ({r.status_code}): {r.text[:600]}")
        return r.json() if r.content else None


def deploy(mb, plan, prune=False):
    colls = [c for c in mb("GET", "/collection") if c.get("name") == plan["collection"] and not c.get("archived")]
    coll_id = colls[0]["id"] if colls else mb("POST", "/collection", {"name": plan["collection"]})["id"]
    items = mb("GET", f"/collection/{coll_id}/items?models=card&models=dataset&models=metric&models=dashboard")["data"]
    # Match by (type, name): a model and a metric may share a name (e.g. "Orders").
    kind = {"dataset": "model", "metric": "metric", "card": "question"}
    existing = {(kind[i["model"]], i["name"]): i["id"] for i in items if i["model"] in kind}
    dashboards = {i["name"]: i["id"] for i in items if i["model"] == "dashboard"}
    ids = {}

    def upsert(card):
        body = {k: v for k, v in card.items() if k != "columns"}
        body["collection_id"] = coll_id
        cid = existing.get((card["type"], card["name"]))
        return mb("PUT", f"/card/{cid}", body)["id"] if cid else mb("POST", "/card", body)["id"]

    for m in plan["models"]:
        cid = ids[("model", m["name"])] = upsert(m)
        meta = mb("POST", f"/card/{cid}/query", {})["data"]["results_metadata"]["columns"]
        for col in meta:
            over = m["columns"].get(col["name"], {})
            col["display_name"] = over.get("display_name") or col["display_name"]
            col["semantic_type"] = over.get("semantic_type")
            if over.get("settings"):
                col["settings"] = over["settings"]
        mb("PUT", f"/card/{cid}", {"result_metadata": meta})
    for m in plan["metrics"]:
        ids[("metric", m["name"])] = upsert(resolve(m, ids))
    card_ids = {c["name"]: upsert(resolve(c, ids)) for c in plan["cards"]}

    for d in plan["dashboards"]:
        did = dashboards.get(d["name"]) or mb("POST", "/dashboard", {"name": d["name"], "collection_id": coll_id})["id"]
        dashcards = []
        for i, dc in enumerate(d["dashcards"]):
            cid = card_ids.get(dc["card_name"])
            dashcards.append({"id": -(i + 1), "card_id": cid, "col": dc["col"], "row": dc["row"],
                              "size_x": dc["size_x"], "size_y": dc["size_y"],
                              "visualization_settings": dc["visualization_settings"],
                              "parameter_mappings": [{**pm, "card_id": cid} for pm in dc["parameter_mappings"]]})
        mb("PUT", f"/dashboard/{did}", {"description": d["description"], "parameters": d["parameters"], "dashcards": dashcards})
        print(f"deployed: {d['name']} → {mb.url}/dashboard/{did}")

    if prune:  # archive questions, metrics and models that are no longer in the YAML
        wanted = {("model", m["name"]) for m in plan["models"]} | {("metric", m["name"]) for m in plan["metrics"]} \
                 | {("question", c["name"]) for c in plan["cards"]}
        for key, cid in existing.items():
            if key not in wanted:
                mb("PUT", f"/card/{cid}", {"archived": True})
                print(f"archived: {key[0]} {key[1]!r}")


def main():
    load_dotenv()
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--plan", help="write the resolved payloads to this file instead of deploying")
    p.add_argument("--database-id", type=int)
    p.add_argument("--prune", action="store_true", help="archive items in the collection that the YAML no longer defines")
    args = p.parse_args()
    spec = yaml.safe_load(SPEC.read_text())
    if args.plan:
        plan = build_plan(spec, args.database_id or 0)
        pathlib.Path(args.plan).write_text(json.dumps(plan, ensure_ascii=False))
        print(f"wrote {args.plan}: {len(plan['models'])} models, {len(plan['metrics'])} metrics, "
              f"{len(plan['cards'])} questions, {len(plan['dashboards'])} dashboards")
        return
    mb = Metabase(os.environ.get("MB_URL", "http://localhost:3000"), os.environ["MB_API_KEY"])
    db_id = args.database_id
    if db_id is None:
        name = os.environ.get("MB_DATABASE", "Retail warehouse")
        db_id = next((d["id"] for d in mb("GET", "/database")["data"] if d["name"] == name), None) or sys.exit(f"no database {name!r}")
    deploy(mb, build_plan(spec, db_id), prune=args.prune)


if __name__ == "__main__":
    main()
