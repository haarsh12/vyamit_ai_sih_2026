"""
Keep Railway agent warm by pinging it every 5 minutes.
Run this as a separate Railway service or use an external cron service like cron-job.org
"""

import time
import httpx
import os

LIVEKIT_AGENT_URL = os.getenv("LIVEKIT_AGENT_URL", "http://localhost:54628")
PING_INTERVAL = 300  # 5 minutes in seconds

def ping_agent():
    """Ping the agent's health endpoint to keep it warm."""
    try:
        response = httpx.get(f"{LIVEKIT_AGENT_URL}/health", timeout=10)
        if response.status_code == 200:
            print(f"✅ Agent is warm at {time.strftime('%Y-%m-%d %H:%M:%S')}")
        else:
            print(f"⚠️ Agent responded with status {response.status_code}")
    except Exception as e:
        print(f"❌ Failed to ping agent: {e}")

if __name__ == "__main__":
    print("🔥 Starting agent warmer...")
    while True:
        ping_agent()
        time.sleep(PING_INTERVAL)
