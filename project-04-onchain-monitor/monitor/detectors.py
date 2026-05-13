"""
detectors.py — règles de détection des transactions suspectes
Chaque détecteur reçoit un log/event et retourne une alerte ou None
"""

from dataclasses import dataclass
from typing      import Optional
import json

# Signatures des events surveillés (keccak256 des signatures)
# Générées avec : cast keccak "EventName(types)"
EVENT_SIGNATURES = {
    "AdminChanged":    "0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f",
    "AdminProposed":   "0xa44dcbe1fb5e26d0b44e5428e4f083f75614960aab11a5f6e75b0fc6d61e7e36",
    "Mint":            "0x0f6798a560793a54c3bcfe86a93cde1e73087d944c0ea20544137d4121396885",
    "EmergencyDrain":  "0x2da466a7b24304f47e87fa2e1e5a81b9831ce54fec19055ce277ca2f39ba42c4",
    "LargeTransfer":   "0x9b1bfa7fa9ee420a16e124f794c35ac9f90472acc99140eb2f6447c714cad8eb",
    "Paused":          "0x62e78cea01bee320cd4e420270b5ea74000d11b0c9f74754ebdbfc544b05a258",
}

SEVERITY_CRITICAL = "CRITICAL"
SEVERITY_HIGH     = "HIGH"
SEVERITY_MEDIUM   = "MEDIUM"
SEVERITY_LOW      = "LOW"

@dataclass
class Alert:
    severity:    str
    event_name:  str
    description: str
    tx_hash:     str
    block:       int
    data:        dict

def decode_address(topic: str) -> str:
    """Extrait une adresse d'un topic (32 bytes → 20 bytes)"""
    return "0x" + topic[-40:]

def detect(log: dict) -> Optional[Alert]:
    """
    Analyse un log et retourne une alerte si suspect.
    log : dict avec keys topics, data, transactionHash, blockNumber
    """
    topics    = log.get("topics", [])
    tx_hash   = log.get("transactionHash", "")
    block_num = int(log.get("blockNumber", "0x0"), 16)

    if not topics:
        return None

    event_sig = topics[0].lower()

    # ── CRITICAL : AdminChanged ───────────────────────────
    if event_sig == EVENT_SIGNATURES["AdminChanged"].lower():
        old_admin = decode_address(topics[1]) if len(topics) > 1 else "unknown"
        new_admin = decode_address(topics[2]) if len(topics) > 2 else "unknown"
        return Alert(
            severity    = SEVERITY_CRITICAL,
            event_name  = "AdminChanged",
            description = f"Admin changed from {old_admin} to {new_admin}",
            tx_hash     = tx_hash,
            block       = block_num,
            data        = {"old_admin": old_admin, "new_admin": new_admin},
        )

    # ── CRITICAL : EmergencyDrain ─────────────────────────
    if event_sig == EVENT_SIGNATURES["EmergencyDrain"].lower():
        to = decode_address(topics[1]) if len(topics) > 1 else "unknown"
        return Alert(
            severity    = SEVERITY_CRITICAL,
            event_name  = "EmergencyDrain",
            description = f"Emergency drain executed → {to}",
            tx_hash     = tx_hash,
            block       = block_num,
            data        = {"to": to},
        )

    # ── HIGH : AdminProposed ──────────────────────────────
    if event_sig == EVENT_SIGNATURES["AdminProposed"].lower():
        proposed = decode_address(topics[1]) if len(topics) > 1 else "unknown"
        return Alert(
            severity    = SEVERITY_HIGH,
            event_name  = "AdminProposed",
            description = f"New admin proposed: {proposed}",
            tx_hash     = tx_hash,
            block       = block_num,
            data        = {"proposed": proposed},
        )

    # ── HIGH : Mint ───────────────────────────────────────
    if event_sig == EVENT_SIGNATURES["Mint"].lower():
        to = decode_address(topics[1]) if len(topics) > 1 else "unknown"
        return Alert(
            severity    = SEVERITY_HIGH,
            event_name  = "Mint",
            description = f"Tokens minted to {to}",
            tx_hash     = tx_hash,
            block       = block_num,
            data        = {"to": to},
        )

    # ── MEDIUM : LargeTransfer ────────────────────────────
    if event_sig == EVENT_SIGNATURES["LargeTransfer"].lower():
        frm = decode_address(topics[1]) if len(topics) > 1 else "unknown"
        to  = decode_address(topics[2]) if len(topics) > 2 else "unknown"
        return Alert(
            severity    = SEVERITY_MEDIUM,
            event_name  = "LargeTransfer",
            description = f"Large transfer detected: {frm} → {to}",
            tx_hash     = tx_hash,
            block       = block_num,
            data        = {"from": frm, "to": to},
        )

    # ── MEDIUM : Paused ───────────────────────────────────
    if event_sig == EVENT_SIGNATURES["Paused"].lower():
        by = decode_address(topics[1]) if len(topics) > 1 else "unknown"
        return Alert(
            severity    = SEVERITY_MEDIUM,
            event_name  = "Paused",
            description = f"Protocol paused by {by}",
            tx_hash     = tx_hash,
            block       = block_num,
            data        = {"by": by},
        )

    return None