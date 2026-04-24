#!/usr/bin/env python3
"""
Serveur HTTP local — expose Slither comme une API REST pour n8n.
POST /audit  { "contract": "contracts/VulnerableBank.sol" }
GET  /health
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, UTC
import json
import subprocess
import sys
import os

PORT = 8765
SEVERITY_MAP = {
    "reentrancy-eth":          "CRITICAL",
    "reentrancy-no-eth":       "HIGH",
    "uninitialized-local":     "HIGH",
    "controlled-delegatecall": "CRITICAL",
    "arbitrary-send-eth":      "CRITICAL",
    "suicidal":                "CRITICAL",
    "tx-origin":               "MEDIUM",
    "solc-version":            "MEDIUM",
    "low-level-calls":         "INFORMATIONAL",
    "calls-loop":              "MEDIUM",
}

def run_slither(contract_path):
    result = subprocess.run(
        ["slither", contract_path, "--json", "-"],
        capture_output=True, text=True,
        cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        try:
            return json.loads(result.stderr)
        except json.JSONDecodeError:
            return {"success": False, "error": result.stderr}

def parse_and_report(contract_path):
    raw = run_slither(contract_path)
    findings = []
    for item in raw.get("results", {}).get("detectors", []):
        detector = item.get("check", "unknown")
        severity = SEVERITY_MAP.get(detector, item.get("impact", "UNKNOWN").upper())
        findings.append({
            "detector":    detector,
            "severity":    severity,
            "description": item.get("description", "").strip(),
            "location":    item.get("elements", [{}])[0].get("name", "unknown"),
        })
    critical_high = [f for f in findings if f["severity"] in ("CRITICAL", "HIGH")]
    return {
        "contract":    contract_path,
        "timestamp":   datetime.now(UTC).isoformat(),
        "total":       len(findings),
        "needs_alert": len(critical_high) > 0,
        "summary": {
            "CRITICAL":      sum(1 for f in findings if f["severity"] == "CRITICAL"),
            "HIGH":          sum(1 for f in findings if f["severity"] == "HIGH"),
            "MEDIUM":        sum(1 for f in findings if f["severity"] == "MEDIUM"),
            "LOW":           sum(1 for f in findings if f["severity"] == "LOW"),
            "INFORMATIONAL": sum(1 for f in findings if f["severity"] == "INFORMATIONAL"),
        },
        "findings": findings,
    }

class AuditHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        print(f"[{datetime.now(UTC).strftime('%H:%M:%S')}] {format % args}")

    def send_json(self, code, data):
        body = json.dumps(data, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"status": "ok", "port": PORT})
        else:
            self.send_json(404, {"error": "Not found"})

    def do_POST(self):
        if self.path != "/audit":
            self.send_json(404, {"error": "Not found"})
            return
        length = int(self.headers.get("Content-Length", 0))
        body   = self.rfile.read(length)
        try:
            payload  = json.loads(body)
            contract = payload.get("contract", "")
            if not contract:
                self.send_json(400, {"error": "Missing 'contract' field"})
                return
            print(f"[*] Auditing: {contract}")
            report = parse_and_report(contract)
            self.send_json(200, report)
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), AuditHandler)
    print(f"[*] Audit server running on http://localhost:{PORT}")
    print(f"[*] POST /audit  {{\"contract\": \"contracts/VulnerableBank.sol\"}}")
    print(f"[*] GET  /health")
    print(f"[*] Ctrl+C to stop\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Server stopped.")