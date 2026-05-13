#!/usr/bin/env python3
"""
monitor.py — surveille les transactions on-chain en temps réel
Se connecte à Anvil via HTTP polling (pas besoin de websocket)
"""

import requests
import json
import time
import sys
import os
from datetime import datetime, UTC
from detectors import detect
from alerter   import send_alert, should_alert

def load_config() -> dict:
    config_path = os.path.join(os.path.dirname(__file__), "config.json")
    if not os.path.exists(config_path):
        print("[-] config.json not found. Run: node anvil/deploy.js")
        sys.exit(1)
    with open(config_path) as f:
        return json.load(f)

def rpc_call(url: str, method: str, params: list) -> dict:
    payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    resp    = requests.post(url, json=payload, timeout=10)
    return resp.json()

def get_logs(rpc_url: str, contract: str, from_block: int, to_block: int) -> list:
    result = rpc_call(rpc_url, "eth_getLogs", [{
        "address":   contract,
        "fromBlock": hex(from_block),
        "toBlock":   hex(to_block),
    }])
    return result.get("result", [])

def get_latest_block(rpc_url: str) -> int:
    result = rpc_call(rpc_url, "eth_blockNumber", [])
    return int(result.get("result", "0x0"), 16)

def main():
    config   = load_config()
    rpc_url  = config["rpcUrl"]
    contract = config["contractAddress"]

    print(f"[*] Threat Monitor starting...")
    print(f"[*] RPC     : {rpc_url}")
    print(f"[*] Contract: {contract}")
    print(f"[*] Polling every 2 seconds\n")

    last_block = get_latest_block(rpc_url)
    print(f"[*] Starting from block {last_block}")

    alert_count = 0

    while True:
        try:
            current_block = get_latest_block(rpc_url)

            if current_block > last_block:
                logs = get_logs(rpc_url, contract, last_block + 1, current_block)

                for log in logs:
                    alert = detect(log)
                    if alert:
                        ts = datetime.now(UTC).strftime("%H:%M:%S")
                        print(f"[{ts}] [{alert.severity}] {alert.event_name}: {alert.description}")
                        print(f"         tx: {alert.tx_hash}")

                        if should_alert(alert):
                            sent = send_alert(alert)
                            if sent:
                                alert_count += 1
                                print(f"         → Alert sent to n8n (total: {alert_count})")

                last_block = current_block

            time.sleep(2)

        except KeyboardInterrupt:
            print(f"\n[*] Monitor stopped. {alert_count} alerts sent.")
            break
        except Exception as e:
            print(f"[-] Error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()