"""
Symulacja tego co robi Godot - test end-to-end
"""

from ask_model import ask_model, initialize_model

def test_godot_like_scenario():
    """Test scenariusza podobnego do tego w Godot"""
    print("=" * 60)
    print("Test symulacji Godot")
    print("=" * 60)
    
    # Inicjalizacja modelu
    print("\n1. Inicjalizacja modelu...")
    if not initialize_model():
        print("✗ Nie udało się zainicjalizować modelu")
        return False
    
    # Symulacja kilku pasażerów
    passengers = [
        {"id": 1, "position": 0, "target": 50, "time": 100},
        {"id": 2, "position": 10, "target": 90, "time": 150},
        {"id": 3, "position": 25, "target": 5, "time": 200},
        {"id": 4, "position": 80, "target": 20, "time": 250},
        {"id": 5, "position": 45, "target": 45, "time": 300},  # Ten sam cel
    ]
    
    print("\n2. Testowanie decyzji dla pasażerów:")
    print("-" * 60)
    
    action_map = {0: "UP", 1: "DOWN", 2: "RIGHT", 3: "LEFT", 4: "WAIT"}
    
    for passenger in passengers:
        action = ask_model(passenger)
        action_code = ["UP", "DOWN", "LEFT", "RIGHT", "WAIT"].index(action.value)
        
        print(f"Pasażer {passenger['id']}:")
        print(f"  Pozycja: {passenger['position']} -> Cel: {passenger['target']}")
        print(f"  Czas: {passenger['time']}")
        print(f"  Akcja: {action.value} (kod: {action_code})")
        print()
    
    print("=" * 60)
    print("✓ Test zakończony pomyślnie!")
    print("=" * 60)
    return True

if __name__ == "__main__":
    test_godot_like_scenario()

