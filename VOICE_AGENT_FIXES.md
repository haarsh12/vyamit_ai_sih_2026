# Voice Agent Issues and Fixes

## Issue Analysis

### Problem 1: Agent Not Recognizing Inventory Items
**Symptom**: When user asks "चावल कितने रुपए किलो है?" (What is the price of rice per kg?), the agent responds "हमारे पास चावल अभी उपलब्ध नहीं है" (We don't have rice available) even though rice exists in inventory.

**Root Cause**: The LLM is misinterpreting the search results from `search_inventory` tool. The tool returns:
```json
{
  "matches": [
    {
      "id": "custom_1787415881737_chawal",
      "names": ["chawal"],
      "category": "Daily Essentials",
      "price": "56.00",
      "unit": "kg",
      "gst_rate": "0",
      "match_score": 0.9,
      "match_source": "substring"
    }
  ],
  "catalog_has_quantity_tracking": false
}
```

But the LLM is not recognizing this as a successful match.

**Fixes Applied**:
1. ✅ Added explicit INVENTORY SEARCH RULES to agent instructions
2. ✅ Added logging to `search_inventory` tool to track what's being returned
3. ✅ Added logging to `create_bill_draft` tool to track when items are added

### Problem 2: Items Not Appearing in Live Bill Box
**Symptom**: When the agent says it added items to the bill, they don't appear in the Flutter app's live bill box.

**Root Cause**: The agent is not actually calling the `create_bill_draft` tool when users ask to add items.

**Expected Flow**:
1. User: "1 kg chawal add karo" (Add 1 kg rice)
2. Agent searches inventory → finds rice at ₹56/kg
3. Agent calls `create_bill_draft` with items=[{name: "chawal", quantity: 1, unit: "kg", price: 56}]
4. Backend creates WorkflowDraft and publishes `bill_draft` event via LiveKit data channel
5. Flutter app receives event and updates BillProvider
6. UI shows item in live bill box

**Investigation Needed**:
- Check LiveKit agent logs for `create_bill_draft_called` entries
- Verify the event is being published via `_publish_ui_event`
- Check Flutter logs for incoming `bill_draft` events

## Files Modified

1. `backend_app/app/agent/instructions.py`
   - Added INVENTORY SEARCH RULES section
   - Clarified how to interpret search results
   - Emphasized immediate bill draft creation

2. `backend_app/app/agent/tools.py`
   - Added logging to `search_inventory` method
   - Added logging to `create_bill_draft` method

## Testing Steps

1. Start the backend voice agent server
2. Connect from Flutter app
3. Ask: "चावल कितने रुपए किलो है?"
   - Expected: Agent should respond with "चावल ₹56 प्रति किलो है"
4. Ask: "1 kg chawal bill me add karo"
   - Expected: Agent should call create_bill_draft
   - Expected: Item should appear in live bill box
   - Expected: Agent should confirm "मैंने 1 किलो चावल ₹56 में बिल में जोड़ दिया है"

## Next Steps

1. ✅ Update agent instructions
2. ✅ Add logging
3. ⏳ Test with new session
4. ⏳ Check logs for tool execution
5. ⏳ Verify LiveKit data channel events
6. ⏳ Verify Flutter app receives and processes events

## Additional Observations

- The inventory search logic is working correctly (verified with test_search_debug.py)
- The transliteration map correctly maps "चावल" → ["rice", "chawal"]
- The database has the item with names=["chawal"]
- The search returns the correct match with score 0.9

The issue is purely in the LLM's interpretation of the tool results, not in the search logic itself.
