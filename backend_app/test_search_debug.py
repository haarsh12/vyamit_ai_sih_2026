"""Debug script to test inventory search for 'chawal'"""

import asyncio
import sys
from app.db.session import get_agent_db_session
from app.db.tenant import TenantContext
from app.retrieval.inventory import inventory_search_service
from sqlalchemy import select
from app.db.models import Item

async def debug_search():
    # Create tenant context matching the voice session
    tenant = TenantContext(
        owner_id=5,
        shop_category="General",
        session_id=None
    )
    
    query = "चावल"  # Hindi for "rice"
    
    async with get_agent_db_session() as session:
        # First, check what items exist
        items = (await session.scalars(
            select(Item).where(
                Item.owner_id == tenant.owner_id,
                Item.shop_category == tenant.shop_category
            )
        )).all()
        
        print(f"=== Database Items for owner_id={tenant.owner_id}, shop_category={tenant.shop_category} ===")
        print(f"Total items: {len(items)}")
        for item in items:
            print(f"  - ID: {item.master_id}")
            print(f"    Names: {item.names}")
            print(f"    Category: {item.category}")
            print(f"    Price: {item.price}")
            print()
        
        # Now test the search
        print(f"\n=== Testing search with query: '{query}' ===")
        matches = await inventory_search_service.search(session, tenant, query)
        
        print(f"Search returned {len(matches)} matches:")
        for match in matches:
            print(f"  - {match.item.names[0]} (score: {match.score}, source: {match.source})")
            print(f"    Price: {match.item.price}")
            print(f"    Payload: {match.to_tool_payload()}")
        
        if not matches:
            print("  NO MATCHES FOUND!")
            print("\n=== Debugging search logic ===")
            
            # Import the search logic helpers
            from app.retrieval.inventory import _tokens, STOP_WORDS, TRANSLITERATION_MAP
            
            query_key = query.strip().casefold()
            query_tokens = {t for t in _tokens(query) if t not in STOP_WORDS}
            
            print(f"Query: '{query}'")
            print(f"Query key (casefold): '{query_key}'")
            print(f"Query tokens: {query_tokens}")
            print()
            
            for item in items:
                print(f"Testing item: {item.names[0]}")
                
                # Test exact match
                exact = any(name.casefold() == query_key for name in item.names)
                print(f"  Exact match: {exact}")
                
                # Test substring match
                item_all_names = " ".join([*item.names, item.category or "", item.master_id or ""]).casefold()
                print(f"  Item all names: '{item_all_names}'")
                
                match_found = False
                for t in query_tokens:
                    if t in item_all_names:
                        print(f"    Token '{t}' found in item_all_names")
                        match_found = True
                    for name in item.names:
                        if t in name.casefold() or name.casefold() in t:
                            print(f"    Token '{t}' matches name '{name}'")
                            match_found = True
                
                print(f"  Substring match: {match_found}")
                print()

if __name__ == "__main__":
    asyncio.run(debug_search())
