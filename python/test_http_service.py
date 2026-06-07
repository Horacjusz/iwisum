"""
Test serwisu HTTP - sprawdza czy Flask endpoint działa
"""

import requests
import time
import subprocess
import sys
import signal

def test_http_service():
    """Test serwisu HTTP"""
    print("=" * 60)
    print("Test serwisu HTTP")
    print("=" * 60)
    
    # Uruchom serwis w tle
    print("\n1. Uruchamianie serwisu...")
    process = subprocess.Popen(
        [sys.executable, "ask_model_service.py", "--host", "127.0.0.1", "--port", "8000"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    # Poczekaj aż serwis się uruchomi
    print("2. Czekanie na uruchomienie serwisu...")
    time.sleep(3)
    
    try:
        # Test health endpoint
        print("\n3. Test /health endpoint...")
        response = requests.get("http://127.0.0.1:8000/health", timeout=2)
        if response.status_code == 200 and response.json().get("status") == "ok":
            print("✓ Health check OK")
        else:
            print(f"✗ Health check failed: {response.status_code}")
            return False
        
        # Test ask_model endpoint
        print("\n4. Test /ask_model endpoint...")
        observation = {
            "id": 1,
            "position": 5,
            "target": 10,
            "time": 100
        }
        response = requests.post(
            "http://127.0.0.1:8000/ask_model",
            json=observation,
            timeout=2
        )
        
        if response.status_code == 200:
            data = response.json()
            print(f"✓ Otrzymano odpowiedź:")
            print(f"  Action code: {data.get('action')}")
            print(f"  Action name: {data.get('action_name')}")
            print(f"  Passenger ID: {data.get('id')}")
            
            if data.get('action') in [0, 1, 2, 3, 4]:
                print("✓ Akcja jest poprawna")
            else:
                print("✗ Niepoprawna akcja")
                return False
        else:
            print(f"✗ Request failed: {response.status_code}")
            return False
        
        # Test batch endpoint
        print("\n5. Test /ask_model_batch endpoint...")
        batch_data = {
            "passengers": [
                {"id": 1, "position": 0, "target": 50, "time": 100},
                {"id": 2, "position": 10, "target": 90, "time": 150},
                {"id": 3, "position": 25, "target": 5, "time": 200},
            ]
        }
        response = requests.post(
            "http://127.0.0.1:8000/ask_model_batch",
            json=batch_data,
            timeout=2
        )
        
        if response.status_code == 200:
            data = response.json()
            actions = data.get('actions', [])
            print(f"✓ Otrzymano {len(actions)} akcji dla {len(batch_data['passengers'])} pasażerów")
            for action in actions:
                print(f"  Pasażer {action.get('id')}: {action.get('action_name')}")
        else:
            print(f"✗ Batch request failed: {response.status_code}")
            return False
        
        print("\n" + "=" * 60)
        print("✓ Wszystkie testy HTTP przeszły pomyślnie!")
        print("=" * 60)
        return True
        
    except requests.exceptions.RequestException as e:
        print(f"\n✗ Błąd połączenia: {e}")
        return False
    except Exception as e:
        print(f"\n✗ Nieoczekiwany błąd: {e}")
        return False
    finally:
        # Zatrzymaj serwis
        print("\n6. Zatrzymywanie serwisu...")
        process.send_signal(signal.SIGTERM)
        process.wait(timeout=5)
        print("✓ Serwis zatrzymany")

if __name__ == "__main__":
    success = test_http_service()
    sys.exit(0 if success else 1)

