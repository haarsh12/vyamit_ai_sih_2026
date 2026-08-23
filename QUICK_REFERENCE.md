# Voice Agent Fix - Quick Reference Card

## 🚨 Quick Deploy

```powershell
# 1. Restart agent server
cd backend_app
# Stop current process, then:
python -m app.agent.runner

# 2. Test it works
python test_voice_integration.py
# Should see: 🎉 ALL TESTS PASSED! 🎉

# 3. Try real session
# From Flutter app, say: "चावल कितने रुपए किलो है?"
# Expected: Agent gives price (not "not available")
```

## ✅ What Changed

| File | Change | Why |
|------|--------|-----|
| `app/agent/instructions.py` | Added explicit inventory interpretation rules | LLM wasn't understanding tool results |
| `app/agent/tools.py` | Added logging to search and bill draft | Track what's happening |
| `app/agent/runner.py` | Added logging to event publishing | Verify events reach Flutter |

## 🧪 Test Commands

```powershell
# Quick inventory search test
cd backend_app
python -c "
import asyncio
from app.db.session import get_agent_db_session
from app.retrieval.inventory import inventory_search_service
from app.db.tenant import TenantContext

async def test():
    tenant = TenantContext(owner_id=5, shop_category='General', session_id=None)
    async with get_agent_db_session() as session:
        result = await inventory_search_service.search(session, tenant, 'चावल')
        print(f'Found {len(result)} matches')

asyncio.run(test())
"

# Full integration tests
python test_voice_integration.py
```

## 📊 Key Logs to Watch

```bash
# When user asks price
search_inventory_result: matches_count=1     # ✓ Item found

# When user adds to bill
create_bill_draft_called: items=[...]        # ✓ Tool called
ui_event_published: event_type=bill_draft    # ✓ Event sent

# If errors
agent_rejected_*                             # ✗ Connection issue
IntegrityError                               # ✗ Database issue
```

## 🐛 Quick Troubleshooting

| Problem | Check | Fix |
|---------|-------|-----|
| "Not available" for existing items | `search_inventory_result` log | Restart agent server |
| Items not in bill box | `create_bill_draft_called` log | Check LiveKit connection |
| Wrong prices | Draft payload in logs | Check catalog prices |

## 📱 Expected Behavior

### Price Query
```
👤: "चावल कितने रुपए किलो है?"
🤖: "चावल ₹56 प्रति किलो है"
📝: search_inventory_result: matches_count=1
```

### Add to Bill
```
👤: "1 kg chawal bill me add karo"
🤖: "मैंने 1 किलो चावल ₹56 में बिल में जोड़ दिया है"
📱: Item appears in bill box
📝: create_bill_draft_called, ui_event_published
```

## 🔄 Rollback (If Needed)

```powershell
git checkout HEAD~1 -- backend_app/app/agent/instructions.py
git checkout HEAD~1 -- backend_app/app/agent/tools.py
git checkout HEAD~1 -- backend_app/app/agent/runner.py
# Restart agent server
```

## 📞 Quick Help

1. **Run tests first**: `python test_voice_integration.py`
2. **Check logs**: Look for `search_inventory_result` and `create_bill_draft_called`
3. **Verify agent restarted**: New code only loads on restart
4. **Test with known item**: "chawal" exists at ₹56/kg for owner_id=5

## 🎯 Success Checklist

- [ ] Agent server restarted
- [ ] Integration tests pass (4/4)
- [ ] Real session connects
- [ ] Price queries return correct prices
- [ ] Items added to bill appear in Flutter app
- [ ] No errors in logs

---

**Status**: ✅ All fixes tested and working
**Next**: Deploy to production (restart agent server)
