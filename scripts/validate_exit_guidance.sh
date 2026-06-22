#!/bin/bash
# Prova operacional do guiamento de SAÍDA: bate no Valhalla de produção, confirma o campo
# estruturado `exit_number_elements` e decodifica com as MESMAS structs do app → deve dar "282".
# Uso: bash scripts/validate_exit_guidance.sh
set -e
TMP=$(mktemp -d)
curl -s --max-time 25 "https://valhalla.truckereasy.com/route" -H "Content-Type: application/json" \
  -d '{"locations":[{"lat":40.5800,"lon":-111.8900},{"lat":40.4150,"lon":-111.8650}],"costing":"truck","directions_options":{"units":"miles"}}' \
  -o "$TMP/resp.json"
python3 -c "
import json,sys
d=json.load(open('$TMP/resp.json'))
for m in d['trip']['legs'][0]['maneuvers']:
    s=m.get('sign',{})
    if 'exit_number_elements' in s:
        json.dump(s,open('$TMP/sign.json','w')); print('Valhalla:',m['instruction']); sys.exit(0)
print('FALHA: nenhum exit_number_elements'); sys.exit(1)
"
cat > "$TMP/t.swift" <<'SWIFT'
import Foundation
struct ValhallaSign: Decodable {
    let exitNumber: [Element]?; let exitToward: [Element]?
    struct Element: Decodable { let text: String }
    enum CodingKeys: String, CodingKey { case exitNumber="exit_number_elements"; case exitToward="exit_toward_elements" }
    var num: String? { exitNumber?.map(\.text).joined(separator:"/") }
    var toward: String? { exitToward?.map(\.text).joined(separator:", ") }
}
let s = try! JSONDecoder().decode(ValhallaSign.self, from: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let num = s.num ?? "nil"
print("Decodificado: exit=\(num) toward=\(s.toward ?? "nil")")
exit(num == "282" ? 0 : 1)
SWIFT
swift "$TMP/t.swift" "$TMP/sign.json"
echo "✅ PASS: saída estruturada do Valhalla decodifica = 282 (real, não regex)"
