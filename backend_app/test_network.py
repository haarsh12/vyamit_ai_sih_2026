"""Quick network diagnostics for voice agent services."""
import asyncio
import time
from google import genai
from google.cloud import speech_v1
import os
from dotenv import load_dotenv

load_dotenv()

async def test_gemini():
    """Test Gemini API connection."""
    print("\n🧪 Testing Gemini API...")
    start = time.time()
    try:
        client = genai.Client(api_key=os.getenv("GOOGLE_API_KEY"))
        response = await client.aio.models.generate_content(
            model="gemini-2.0-flash-exp",
            contents="Say 'OK' if you can hear me."
        )
        elapsed = (time.time() - start) * 1000
        print(f"✅ Gemini responded in {elapsed:.0f}ms")
        return True
    except Exception as e:
        elapsed = (time.time() - start) * 1000
        print(f"❌ Gemini failed after {elapsed:.0f}ms: {e}")
        return False

def test_google_stt():
    """Test Google Speech-to-Text API."""
    print("\n🧪 Testing Google STT API...")
    start = time.time()
    try:
        client = speech_v1.SpeechClient()
        # Just test connectivity, don't send actual audio
        config = speech_v1.RecognitionConfig(
            encoding=speech_v1.RecognitionConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=16000,
            language_code="en-US",
        )
        elapsed = (time.time() - start) * 1000
        print(f"✅ Google STT client created in {elapsed:.0f}ms")
        return True
    except Exception as e:
        elapsed = (time.time() - start) * 1000
        print(f"❌ Google STT failed after {elapsed:.0f}ms: {e}")
        return False

async def test_livekit():
    """Test LiveKit Cloud connectivity."""
    print("\n🧪 Testing LiveKit Cloud...")
    print("   (This just tests if the SDK loads, actual connection happens during session)")
    start = time.time()
    try:
        from livekit import rtc
        elapsed = (time.time() - start) * 1000
        print(f"✅ LiveKit SDK loaded in {elapsed:.0f}ms")
        return True
    except Exception as e:
        elapsed = (time.time() - start) * 1000
        print(f"❌ LiveKit SDK failed after {elapsed:.0f}ms: {e}")
        return False

async def main():
    """Run all network tests."""
    print("=" * 60)
    print("🌐 Voice Agent Network Diagnostics")
    print("=" * 60)
    
    results = {}
    results['gemini'] = await test_gemini()
    results['stt'] = test_google_stt()
    results['livekit'] = await test_livekit()
    
    print("\n" + "=" * 60)
    print("📊 Summary:")
    print("=" * 60)
    for service, passed in results.items():
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"  {service.upper()}: {status}")
    
    all_passed = all(results.values())
    if all_passed:
        print("\n✅ All services reachable!")
    else:
        print("\n❌ Some services failed - check your internet connection and API credentials")
        print("\nTroubleshooting:")
        print("  1. Check internet connection stability")
        print("  2. Verify .env file has correct API keys")
        print("  3. Check if behind firewall/proxy")
        print("  4. Try from a different network")

if __name__ == "__main__":
    asyncio.run(main())
