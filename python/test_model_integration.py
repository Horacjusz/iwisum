"""
Test script to verify model integration with Godot simulation.
"""

from ask_model import initialize_model, ask_model, validate_observation
from environment import Action

def test_initialization():
    """Test model initialization."""
    print("=" * 60)
    print("Testing Model Initialization")
    print("=" * 60)
    
    success = initialize_model()
    if success:
        print("✓ Model initialized successfully")
        return True
    else:
        print("✗ Model initialization failed")
        return False

def test_observation_validation():
    """Test observation validation."""
    print("\n" + "=" * 60)
    print("Testing Observation Validation")
    print("=" * 60)
    
    # Valid observation
    valid_obs = {
        "id": 1,
        "position": 5,
        "target": 10,
        "time": 100
    }
    
    if validate_observation(valid_obs):
        print("✓ Valid observation accepted")
    else:
        print("✗ Valid observation rejected")
        return False
    
    # Invalid observations
    invalid_obs_list = [
        {},
        {"position": 5},
        {"position": 5, "target": 10},
        None,
        "not a dict"
    ]
    
    for invalid_obs in invalid_obs_list:
        if not validate_observation(invalid_obs):
            print(f"✓ Invalid observation rejected: {invalid_obs}")
        else:
            print(f"✗ Invalid observation accepted: {invalid_obs}")
            return False
    
    return True

def test_model_inference():
    """Test model inference."""
    print("\n" + "=" * 60)
    print("Testing Model Inference")
    print("=" * 60)
    
    # Test observations
    test_cases = [
        {"id": 1, "position": 0, "target": 10, "time": 100},
        {"id": 2, "position": 5, "target": 15, "time": 200},
        {"id": 3, "position": 10, "target": 5, "time": 300},
        {"id": 4, "position": 20, "target": 0, "time": 400},
    ]
    
    for obs in test_cases:
        action = ask_model(obs)
        if isinstance(action, Action):
            print(f"✓ Passenger {obs['id']}: pos={obs['position']}, target={obs['target']} -> {action.value}")
        else:
            print(f"✗ Invalid action returned for passenger {obs['id']}")
            return False
    
    return True

def test_edge_cases():
    """Test edge cases."""
    print("\n" + "=" * 60)
    print("Testing Edge Cases")
    print("=" * 60)
    
    # Same position and target
    obs = {"id": 5, "position": 10, "target": 10, "time": 100}
    action = ask_model(obs)
    print(f"✓ Same position and target: {action.value}")
    
    # Very high time value
    obs = {"id": 6, "position": 0, "target": 20, "time": 1400}
    action = ask_model(obs)
    print(f"✓ High time value: {action.value}")
    
    # None observation
    action = ask_model(None)
    if action == Action.WAIT:
        print(f"✓ None observation returns WAIT: {action.value}")
    else:
        print(f"✗ None observation should return WAIT, got: {action.value}")
        return False
    
    return True

def main():
    """Run all tests."""
    print("\n" + "=" * 60)
    print("MODEL INTEGRATION TEST SUITE")
    print("=" * 60 + "\n")
    
    tests = [
        ("Initialization", test_initialization),
        ("Observation Validation", test_observation_validation),
        ("Model Inference", test_model_inference),
        ("Edge Cases", test_edge_cases),
    ]
    
    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"\n✗ {test_name} failed with exception: {e}")
            import traceback
            traceback.print_exc()
            results.append((test_name, False))
    
    # Print summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, result in results:
        status = "✓ PASSED" if result else "✗ FAILED"
        print(f"{status}: {test_name}")
    
    print(f"\nTotal: {passed}/{total} tests passed")
    
    if passed == total:
        print("\n🎉 All tests passed!")
        return 0
    else:
        print(f"\n⚠️  {total - passed} test(s) failed")
        return 1

if __name__ == "__main__":
    exit(main())

