#!/usr/bin/env python3
"""
Slither audit runner — parse les résultats et génère un JSON
structuré pour le pipeline n8n.
"""

import subprocess
import json
import sys
import re
from datetime import datetime, UTC

SEVERITY_MAP = {
    "reentrancy-eth":    "CRITICAL",
    "reentrancy-no-eth": "HIGH",
    "uninitialized-local": "HIGH",
    "controlled-delegatecall": "CRITICAL",
    "arbitrary-send-eth": "CRITICAL",
    "suicidal":          "CRITICAL",
    "tx-origin":         "MEDIUM",
    "solc-version":      "MEDIUM",
    "low-level-calls":   "INFORMATIONAL",
    "calls-loop":        "MEDIUM",
    "events-maths":      "LOW",
}

def run_slither(contract_path: str) -> dict:
    result = subprocess.run(
        ["slither", contract_path, "--json", "-"],
        capture_output=True,
        text=True
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        # Slither écrit parfois sur stderr
        try:
            return json.loads(result.stderr)
        except json.JSONDecodeError:
            return {"success": False, "error": result.stderr}

def parse_findings(slither_output: dict) -> list:
    findings = []
    results = slither_output.get("results", {}).get("detectors", [])

    for item in results:
        detector = item.get("check", "unknown")
        severity = SEVERITY_MAP.get(detector, item.get("impact", "UNKNOWN").upper())
        findings.append({
            "detector":    detector,
            "severity":    severity,
            "description": item.get("description", "").strip(),
            "location":    item.get("elements", [{}])[0].get("name", "unknown"),
        })
    return findings

def build_report(contract_path: str, findings: list) -> dict:
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

if __name__ == "__main__":
    contract = sys.argv[1] if len(sys.argv) > 1 else "contracts/VulnerableBank.sol"
    print(f"[*] Analyzing: {contract}", file=sys.stderr)

    raw = run_slither(contract)
    findings = parse_findings(raw)
    report = build_report(contract, findings)

    print(json.dumps(report, indent=2))