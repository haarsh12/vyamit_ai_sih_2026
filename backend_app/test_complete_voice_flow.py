"""Complete voice agent flow test - inventory search → bill draft → event publishing."""

import asyncio
import json
from uuid import UUID, uuid4
from app.db.session import get_agent_db_session
from app.db.tenant import TenantContext
from app.agent.tools import VyamitAssistant
from app.agent.instructions import VOICE_ASSISTANT_INSTRUCTIONS


class MockContext:
    """Mock JobContext for testing event publishing."""
    def __init__(self):
        self.events = []
        self.room = type('obj', (object,), {
            'name': 'test-room',
            'local_participant': self
        })()
    
    async def publish_data(self, data, reliable=True, topic=None):
        """Capture published events."""
        event = json.loads(data.decode('utf-8'))
        self.events.append(event)
        print(f"📤 Event published: {event['type']}")
        if event['type'] == 'bill_draft':
            print(f"   Items: {event.get('state', {}).get('items', [])}")


async def test_complete_flow():
    """Test the complete voice agent flow."""
    
    print("\n" + "="*80)
    print("COMPLETE VOICE AGENT FLOW TEST")
    print("="*80)
    
    # Setup tenant context
    tenant = TenantContext(
        owner_id=5,
        shop_category="General",
        session_id=None
    )
    
    # Mock context for event capture
    mock_ctx = MockContext()
    
    # Event tracking
    published_events = []
    
    async def on_bill_draft(draft: dict) -> None:
        """Capture bill draft events."""
        print(f"\n✅ Bill draft callback triggered!")
        print(f"   Draft ID: {draft['draft_id']}")
        print(f"   Items: {draft['state']['items']}")
        published_events.append(('bill_draft', draft))
        
        # Simulate publishing to LiveKit
        await mock_ctx.publish_data(
            json.dumps({"type": "bill_draft", **draft}).encode('utf-8'),
            reliable=True,
            topic="vyamit.ui"
        )
    
    # Create assistant with callback
    assistant = VyamitAssistant(
        instructions=VOICE_ASSISTANT_INSTRUCTIONS,
        tenant=tenant,
        on_bill_draft_created=on_bill_draft
    )
    
    print("\n" + "-"*80)
    print("STEP 1: User asks for price")
    print("-"*80)
    print("👤 User: 'चावल कितने रुपए किलो है?'")
    
    # Step 1: Search inventory
    search_result = await assistant.search_inventory("चावल")
    print(f"\n🔍 Search result: {len(search_result['matches'])} matches")
    
    if not search_result['matches']:
        print("❌ FAILED: No items found in inventory!")
        return False
    
    item = search_result['matches'][0]
    print(f"✅ Found: {item['names'][0]} at ₹{item['price']}/{item['unit']}")
    print(f"🤖 Agent should respond: 'चावल ₹{item['price']} प्रति {item['unit']} है'")
    
    print("\n" + "-"*80)
    print("STEP 2: User asks to add to bill")
    print("-"*80)
    print("👤 User: '1 kg bill me add karo'")
    
    # Step 2: Create bill draft
    bill_items = [{
        "name": item['names'][0],
        "quantity": 1.0,
        "unit": item['unit'],
        "price": float(item['price'])
    }]
    
    print(f"\n🔧 Calling create_bill_draft with items: {bill_items}")
    draft_result = await assistant.create_bill_draft(
        items=bill_items,
        total_amount=float(item['price'])
    )
    
    print(f"\n📋 Bill draft result:")
    print(f"   Created: {draft_result.get('created')}")
    print(f"   Draft ID: {draft_result.get('draft_id')}")
    
    if not draft_result.get('created'):
        print(f"❌ FAILED: Bill draft not created!")
        print(f"   Message: {draft_result.get('message')}")
        return False
    
    print(f"🤖 Agent should respond: 'मैंने 1 {item['unit']} {item['names'][0]} ₹{item['price']} में बिल में जोड़ दिया है'")
    
    # Wait a moment for async callbacks
    await asyncio.sleep(0.5)
    
    print("\n" + "-"*80)
    print("STEP 3: Verify event publishing")
    print("-"*80)
    
    if not published_events:
        print("❌ FAILED: No events captured!")
        return False
    
    print(f"✅ Captured {len(published_events)} event(s)")
    
    # Check bill_draft event
    bill_draft_events = [e for e in published_events if e[0] == 'bill_draft']
    if not bill_draft_events:
        print("❌ FAILED: No bill_draft events found!")
        return False
    
    event_type, event_data = bill_draft_events[0]
    print(f"\n📨 Bill draft event details:")
    print(f"   Type: {event_type}")
    print(f"   State items: {event_data['state']['items']}")
    print(f"   Total: ₹{event_data['state']['total_amount']}")
    
    # Verify LiveKit event was published
    if not mock_ctx.events:
        print("❌ FAILED: No LiveKit events published!")
        return False
    
    livekit_events = [e for e in mock_ctx.events if e['type'] == 'bill_draft']
    if not livekit_events:
        print("❌ FAILED: No bill_draft LiveKit events!")
        return False
    
    print(f"\n📡 LiveKit events published: {len(livekit_events)}")
    print(f"   Event structure: {list(livekit_events[0].keys())}")
    
    # Verify Flutter would receive correct data
    flutter_event = livekit_events[0]
    if 'state' not in flutter_event or 'items' not in flutter_event['state']:
        print("❌ FAILED: Event missing state.items!")
        return False
    
    flutter_items = flutter_event['state']['items']
    print(f"\n📱 Flutter would receive {len(flutter_items)} item(s):")
    for idx, item in enumerate(flutter_items, 1):
        print(f"   {idx}. {item['name']} x {item['quantity']} @ ₹{item['price']} = ₹{item['total']}")
    
    print("\n" + "="*80)
    print("✅ ALL STEPS PASSED!")
    print("="*80)
    print("\nFlow summary:")
    print("  1. ✅ Inventory search found item")
    print("  2. ✅ Bill draft created successfully")
    print("  3. ✅ Callback triggered correctly")
    print("  4. ✅ LiveKit event published")
    print("  5. ✅ Flutter would receive correct data")
    
    return True


async def test_multiple_items():
    """Test adding multiple items to bill."""
    
    print("\n" + "="*80)
    print("MULTIPLE ITEMS TEST")
    print("="*80)
    
    tenant = TenantContext(
        owner_id=5,
        shop_category="General",
        session_id=None
    )
    
    events_captured = []
    
    async def capture_event(draft: dict) -> None:
        events_captured.append(draft)
    
    assistant = VyamitAssistant(
        instructions=VOICE_ASSISTANT_INSTRUCTIONS,
        tenant=tenant,
        on_bill_draft_created=capture_event
    )
    
    # Search for first item
    search1 = await assistant.search_inventory("chawal")
    if not search1['matches']:
        print("❌ Item 1 not found")
        return False
    
    item1 = search1['matches'][0]
    
    # Create bill with multiple items
    items = [
        {"name": item1['names'][0], "quantity": 2.0, "unit": "kg", "price": float(item1['price'])},
        {"name": "Test Item", "quantity": 1.0, "unit": "kg", "price": 50.0},
    ]
    
    result = await assistant.create_bill_draft(items=items)
    await asyncio.sleep(0.5)
    
    if not result.get('created'):
        print("❌ Draft not created")
        return False
    
    if not events_captured:
        print("❌ No events captured")
        return False
    
    draft_items = events_captured[0]['state']['items']
    print(f"✅ Bill created with {len(draft_items)} items:")
    for item in draft_items:
        print(f"   - {item['name']}: {item['quantity']} x ₹{item['price']} = ₹{item['total']}")
    
    total = sum(float(item['total']) for item in draft_items)
    print(f"   Total: ₹{total}")
    
    return True


async def main():
    """Run all tests."""
    print("\n")
    print("="*80)
    print("VOICE AGENT INTEGRATION TEST SUITE")
    print("="*80)
    
    results = []
    
    try:
        results.append(("Complete Flow Test", await test_complete_flow()))
        results.append(("Multiple Items Test", await test_multiple_items()))
    except Exception as e:
        print(f"\n❌ TEST SUITE FAILED WITH ERROR:")
        print(f"   {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return
    
    # Summary
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
        print("\nThe voice agent is ready:")
        print("  ✅ Inventory search working")
        print("  ✅ Bill drafts being created")
        print("  ✅ Events being published")
        print("  ✅ Flutter will receive correct data")
    else:
        print(f"\n⚠️  {total - passed} test(s) failed.")


if __name__ == "__main__":
    asyncio.run(main())
