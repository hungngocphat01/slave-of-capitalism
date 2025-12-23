import urllib.request
import urllib.error
import json
from datetime import date

BASE_URL = "http://127.0.0.1:8000/api/wallets"

def verify_server_audit():
    today = date.today().isoformat()
    
    # Test SERVER-SIDE audit (no balances sent)
    payload = {
        "date": today
        # balances, debts, owed explicitly OMITTED
    }
    
    print("Sending Server-Side Audit Request:", json.dumps(payload))
    
    req = urllib.request.Request(
        f"{BASE_URL}/audits",
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            print(f"POST Status: {response.status}")
            data = json.loads(response.read().decode('utf-8'))
            print("Response:", json.dumps(data, indent=2))
            
            # Verify balances were populated
            if data.get('balances') and len(data['balances']) > 0:
                print("SUCCESS: Server calculated balances:", data['balances'])
            else:
                print("FAILURE: Balances returned empty/null")
                
    except urllib.error.HTTPError as e:
        print(f"POST Failed Status: {e.code}")
        print("Response Body:", e.read().decode('utf-8'))
    except urllib.error.URLError as e:
        print(f"POST Connection Failed: {e}")

if __name__ == "__main__":
    verify_server_audit()
