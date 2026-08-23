"""Integration test to verify voice agent inventory search and bill draft creation."""

import asyncio
import json
from uuid import UUID
from app.db.session import get_agent_db_session
from app.db.tenant import TenantContext
from app.agent.tools import VyamitAssistant
from app.agent.instructions import VOICE_ASSISTANT_INSTRUCTIONS


async def simulate_bill_draft_callback(draft: dict) -> None:
    """Simulate the callback that publishes to LiveKit."""
    print("\n=== BILL DRAFT CALLBACK TRIGGERED ===")
    print(json.dumps(draft, indent=2, default=str))
    print("=== END CALLBACK ===\n")


async def test_inventory_search():
    """Test that inventory search returns correct results."""
    print("\n" + "="*80)
    print("TEST 1: Inventory Search for 'चावल' (rice)")
    print("="*80)
    
    tenant = TenantContext(
        owner_id=5,
        shop_category="General",
        session_id=UUID("12345678-1234-5678-1234-567812345678")
    )
    
    assistant = VyamitAssistant(
        instructions=VOICE_ASSISTANT_INSTRUCTIONS,
        tenant=tenant
    )
    
    # Test search
    result = await assistant.search_inventory("चावल")
    
    print(f"\nSearch Query: 'चावल'")
    print(f"Results: {json.dumps(result, indent=2)}")
    
    if result["matches"]:
        print("\n✅ SUCCESS: Found items in inventory")
        print(f"   Item: {result['matches'][0]['names'][0]}")
        print(f"   Price: ₹{result['matches'][0]['price']}/{result['matches'][0]['unit']}")
        return True
    else:
        print("\n❌ FAILURE: No items found in inventory")
        return False


async def test_bill_draft_creation():
    """Test that bill draft creation works correctly."""
    print("\n" + "="*80)
    print("TEST 2: Bill Draft Creation")
    print("="*80)
    
    # Use None for session_id to test without voice session requirement
    tenant = TenantContext(
        owner_id=5,
        shop_category="General",
        session_id=None  # Allow drafts without voice session
    )
    
    assistant = VyamitAssistant(
        instructions=VOICE_ASSISTANT_INSTRUCTIONS,
        tenant=tenant,
        on_bill_draft_created=simulate_bill_draft_callback
    )
    
    # First search for the item
    search_result = await assistant.search_inventory("chawal")
    
    if not search_result["matches"]:
        print("❌ Cannot test bill draft - no items found")
        return False
    
    item = search_result["matches"][0]
    print(f"\nFound item: {item['names'][0]} at ₹{item['price']}/{item['unit']}")
    
    # Create a bill draft
    print("\nCreating bill draft with 1 kg chawal...")
    bill_items = [
        {
            "name": item['names'][0],
            "quantity": 1.0,
            "unit": item['unit'],
            "price": float(item['price'])
        }
    ]
    
    result = await assistant.create_bill_draft(
        items=bill_items,
        total_amount=float(item['price'])
    )
    
    print(f"\nBill Draft Result:")
    print(json.dumps(result, indent=2, default=str))
    
    if result.get("created"):
        print("\n✅ SUCCESS: Bill draft created successfully")
        print(f"   Draft ID: {result['draft_id']}")
        print(f"   Items: {result['state']['items']}")
        print(f"   Total: ₹{result['state']['total_amount']}")
        return True
    else:
        print(f"\n❌ FAILURE: Bill draft creation failed")
        print(f"   Message: {result.get('message', 'Unknown error')}")
        return False


async def test_full_flow():
    """Test the complete flow: search → create draft."""
    print("\n" + "="*80)
    print("TEST 3: Full Flow - Search and Add to Bill")
    print("="*80)
    
    tenant = TenantContext(
        owner_id=5,
        shop_category="General",
        session_id=None  # Allow without voice session
    )
    
    assistant = VyamitAssistant(
        instructions=VOICE_ASSISTANT_INSTRUCTIONS,
        tenant=tenant,
        on_bill_draft_created=simulate_bill_draft_callback
    )
    
    # Step 1: User asks for price
    print("\n👤 User: 'चावल कितने रुपए किलो है?'")
    search_result = await assistant.search_inventory("चावल")
    
    if not search_result["matches"]:
        print("🤖 Agent: 'हमारे पास चावल अभी उपलब्ध नहीं है।' ❌")
        print("   ISSUE: Agent should have found chawal!")
        return False
    
    item = search_result["matches"][0]
    print(f"🤖 Agent: 'चावल ₹{item['price']} प्रति {item['unit']} है।' ✅")
    
    # Step 2: User asks to add to bill
    print("\n👤 User: '1 kg bill me add karo'")
    
    bill_result = await assistant.create_bill_draft(
        items=[{
            "name": item['names'][0],
            "quantity": 1.0,
            "unit": item['unit'],
            "price": float(item['price'])
        }],
        total_amount=float(item['price'])
    )
    
    if bill_result.get("created"):
        print(f"🤖 Agent: 'मैंने 1 {item['unit']} {item['names'][0]} ₹{item['price']} में बिल में जोड़ दिया है।' ✅")
        print(f"\n📱 Flutter App: Received bill_draft event with {len(bill_result['state']['items'])} item(s)")
        return True
    else:
        print("🤖 Agent: (Failed to add to bill) ❌")
        return False


async def test_transliteration_variants():
    """Test different ways users might ask for rice."""
    print("\n" + "="*80)
    print("TEST 4: Transliteration Variants")
    print("="*80)
    
    tenant = TenantContext(
        owner_id=5,
        shop_category="General",
        session_id=None
    )
    
    assistant = VyamitAssistant(
        instructions=VOICE_ASSISTANT_INSTRUCTIONS,
        tenant=tenant
    )
    
    queries = [
        "चावल",      # Hindi Devanagari
        "chawal",    # English transliteration
        "rice",      # English word
        "चाव",       # Partial Hindi
        "chaw",      # Partial English
    ]
    
    results = []
    for query in queries:
        result = await assistant.search_inventory(query)
        found = len(result["matches"]) > 0
        results.append((query, found))
        status = "✅" if found else "❌"
        print(f"  Query: '{query:15s}' → {status} {'Found' if found else 'Not found'}")
    
    success_count = sum(1 for _, found in results if found)
    print(f"\n{'✅' if success_count >= 3 else '❌'} {success_count}/{len(queries)} queries successful")
    return success_count >= 3


async def main():
    """Run all tests."""
    print("\n")
    print("=" * 80)
    print(" " * 20 + "VOICE AGENT INTEGRATION TESTS")
    print("=" * 80)
    
    results = []
    
    try:
        # Run tests
        results.append(("Inventory Search", await test_inventory_search()))
        results.append(("Bill Draft Creation", await test_bill_draft_creation()))
        results.append(("Full Flow", await test_full_flow()))
        results.append(("Transliteration Variants", await test_transliteration_variants()))
        
    except Exception as e:
        print(f"\n❌ TEST SUITE FAILED WITH ERROR:")
        print(f"   {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return
    
    # Print summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    
    for test_name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"  {status} - {test_name}")
    
    total = len(results)
    passed = sum(1 for _, p in results if p)
    
    print(f"\n  Total: {passed}/{total} tests passed")
    
    if passed == total:
        print("\n🎉 ALL TESTS PASSED! 🎉")
    else:
        print(f"\n⚠️  {total - passed} test(s) failed. Review the logs above.")


if __name__ == "__main__":
    asyncio.run(main())
