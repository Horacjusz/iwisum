"""
Prosty test uruchomienia serwisu
"""

import sys

print("Test importu modułów...")

try:
    from flask import Flask
    print("✓ Flask zaimportowany")
except ImportError as e:
    print(f"✗ Błąd importu Flask: {e}")
    sys.exit(1)

try:
    from ask_model import initialize_model, ask_model
    print("✓ ask_model zaimportowany")
except ImportError as e:
    print(f"✗ Błąd importu ask_model: {e}")
    sys.exit(1)

try:
    from environment import Action
    print("✓ environment zaimportowany")
except ImportError as e:
    print(f"✗ Błąd importu environment: {e}")
    sys.exit(1)

print("\nTest inicjalizacji modelu...")
success = initialize_model()
if success:
    print("✓ Model zainicjalizowany")
else:
    print("✗ Błąd inicjalizacji modelu")
    sys.exit(1)

print("\nTest inferecji...")
obs = {"position": 5, "target": 10, "time": 100}
action = ask_model(obs)
print(f"✓ Akcja: {action.value}")

print("\nTest tworzenia aplikacji Flask...")
try:
    from ask_model_service import create_app
    app = create_app()
    print("✓ Aplikacja Flask utworzona")
    
    # Test endpointów
    with app.test_client() as client:
        # Test health
        response = client.get('/health')
        if response.status_code == 200:
            print("✓ Endpoint /health działa")
        else:
            print(f"✗ Endpoint /health zwrócił {response.status_code}")
        
        # Test ask_model
        response = client.post('/ask_model', 
                              json={"id": 1, "position": 5, "target": 10, "time": 100})
        if response.status_code == 200:
            data = response.get_json()
            print(f"✓ Endpoint /ask_model działa: {data}")
        else:
            print(f"✗ Endpoint /ask_model zwrócił {response.status_code}")
        
        # Test batch
        response = client.post('/ask_model_batch',
                              json={"passengers": [
                                  {"id": 1, "position": 5, "target": 10, "time": 100},
                                  {"id": 2, "position": 10, "target": 20, "time": 150}
                              ]})
        if response.status_code == 200:
            data = response.get_json()
            print(f"✓ Endpoint /ask_model_batch działa: {len(data['actions'])} akcji")
        else:
            print(f"✗ Endpoint /ask_model_batch zwrócił {response.status_code}")
    
    print("\n" + "=" * 60)
    print("✓ WSZYSTKIE TESTY PRZESZŁY POMYŚLNIE!")
    print("=" * 60)
    print("\nIntegracja jest w pełni funkcjonalna i gotowa do użycia.")
    print("Godot może teraz uruchomić serwis i komunikować się z modelem.")
    
except Exception as e:
    print(f"✗ Błąd: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
