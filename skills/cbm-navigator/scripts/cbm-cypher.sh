#!/usr/bin/env bash
# Usage: cbm-cypher.sh dead-code|cross-layer|hubs|routes  [arg1] [arg2]
set -euo pipefail; source "$(dirname "$0")/_project.sh"
case "$1" in
  dead-code)   Q='MATCH (f:Function) WHERE NOT EXISTS { (f)<-[:CALLS]-() } RETURN f.name, coalesce(f.file_path, f.file) LIMIT 100';;
  cross-layer) A="${2:-/controller/}"; B="${3:-/mapper/}"
               Q="MATCH (a)-[:CALLS]->(b) WHERE coalesce(a.file_path, a.file) CONTAINS '$A' AND coalesce(b.file_path, b.file) CONTAINS '$B' RETURN a.name, coalesce(a.file_path, a.file), b.name LIMIT 200";;
  hubs)        Q='MATCH (c:Class) RETURN c.name, coalesce(c.file_path, c.file) ORDER BY c.degree DESC LIMIT 20';;
  routes)      Q='MATCH (r:Route) RETURN r.name, coalesce(r.file_path, r.file) LIMIT 200';;
  *) echo '{"error":"unknown template","hint":"use: dead-code | cross-layer [layerA] [layerB] | hubs | routes"}'; exit 1;;
esac
cbm_call query_graph "$(jq -n --arg p "$PROJECT" --arg q "$Q" '{project:$p, query:$q}')"
