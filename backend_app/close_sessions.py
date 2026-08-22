"""Script to close all active LiveKit sessions."""

import asyncio
from livekit import api
from app.config.settings import get_settings


async def close_all_sessions():
    """Close all active LiveKit rooms/sessions."""
    settings = get_settings()
    
    livekit_api = api.LiveKitAPI(
        url=settings.livekit_url,
        api_key=settings.livekit_api_key.get_secret_value(),
        api_secret=settings.livekit_api_secret.get_secret_value(),
    )
    
    try:
        # List all active rooms
        from livekit.protocol import room as proto_room
        list_request = proto_room.ListRoomsRequest()
        rooms = await livekit_api.room.list_rooms(list_request)
        
        print(f"Found {len(rooms.rooms)} active rooms")
        
        for room in rooms.rooms:
            print(f"Closing room: {room.name} (SID: {room.sid})")
            try:
                delete_request = proto_room.DeleteRoomRequest(room=room.name)
                await livekit_api.room.delete_room(delete_request)
                print(f"  ✓ Closed: {room.name}")
            except Exception as e:
                print(f"  ✗ Failed to close {room.name}: {e}")
        
        print("\nAll rooms processed!")
        
    finally:
        await livekit_api.aclose()


if __name__ == "__main__":
    asyncio.run(close_all_sessions())
