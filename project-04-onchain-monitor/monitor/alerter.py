"""
alerter.py — envoie les alertes vers n8n webhook
"""

import requests
import json
from datetime import datetime, UTC
from detectors import Alert, SEVERITY_CRITICAL, SEVERITY_HIGH

N8N_WEBHOOK = "https://flow.nanoostudio.com/webhook/threat-alert"

SEVERITY_COLORS = {
    SEVERITY_CRITICAL: 0xE24B4A,  # rouge
    SEVERITY_HIGH:     0xE8892B,  # orange
    "MEDIUM":          0xF0C419,  # jaune
    "LOW":             0x4A90D9,  # bleu
}

SEVERITY_EMOJI = {
    SEVERITY_CRITICAL: "🚨",
    SEVERITY_HIGH:     "🔴",
    "MEDIUM":          "🟡",
    "LOW":             "🔵",
}

def send_alert(alert: Alert) -> bool:
    """Envoie une alerte au webhook n8n"""
    emoji    = SEVERITY_EMOJI.get(alert.severity, "⚠️")
    color    = SEVERITY_COLORS.get(alert.severity, 0x888888)

    payload = {
        "severity":    alert.severity,
        "event_name":  alert.event_name,
        "description": alert.description,
        "tx_hash":     alert.tx_hash,
        "block":       alert.block,
        "data":        alert.data,
        "timestamp":   datetime.now(UTC).isoformat(),
        "discord_payload": {
            "username": "ThreatMonitor",
            "embeds": [{
                "title":       f"{emoji} {alert.severity} — {alert.event_name}",
                "description": alert.description,
                "color":       color,
                "fields": [
                    {"name": "Block",    "value": str(alert.block),    "inline": True},
                    {"name": "Tx Hash", "value": f"`{alert.tx_hash[:20]}...`", "inline": True},
                ],
                "footer": {"text": datetime.now(UTC).isoformat()},
            }]
        }
    }

    try:
        resp = requests.post(N8N_WEBHOOK, json=payload, timeout=5)
        resp.raise_for_status()
        return True
    except Exception as e:
        print(f"[-] Failed to send alert: {e}")
        return False

def should_alert(alert: Alert) -> bool:
    """Filtre — envoie seulement CRITICAL et HIGH vers Discord"""
    return alert.severity in (SEVERITY_CRITICAL, SEVERITY_HIGH)