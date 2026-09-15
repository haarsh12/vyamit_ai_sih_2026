#!/usr/bin/env python3
"""
Environment Variable Validation Script for Render Deployment

Run this script locally to verify all required environment variables
are set before deploying to Render.

Usage:
    python check_env.py
"""

import os
import sys
from typing import Dict, List, Tuple

# ANSI color codes
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'


def check_env_var(name: str, required: bool = True, should_be_secret: bool = False) -> Tuple[bool, str]:
    """Check if an environment variable is set."""
    value = os.getenv(name)
    
    if value is None or value.strip() == "":
        if required:
            return False, f"{RED}✗{RESET} {name}: Missing (REQUIRED)"
        else:
            return True, f"{YELLOW}○{RESET} {name}: Not set (optional)"
    
    # Check for placeholder values
    placeholders = ["replace-", "your-", "YOUR-", "changeme", "CHANGEME", "xxx", "XXX"]
    if any(placeholder in value for placeholder in placeholders):
        return False, f"{YELLOW}⚠{RESET} {name}: Contains placeholder value"
    
    # Mask secret values
    if should_be_secret:
        masked = value[:4] + "..." + value[-4:] if len(value) > 8 else "***"
        return True, f"{GREEN}✓{RESET} {name}: Set ({masked})"
    
    return True, f"{GREEN}✓{RESET} {name}: Set"


def main():
    """Main validation function."""
    print(f"\n{BLUE}{'='*60}{RESET}")
    print(f"{BLUE}  Vyamit Backend - Environment Variables Check{RESET}")
    print(f"{BLUE}{'='*60}{RESET}\n")
    
    # Load .env file if it exists
    try:
        from dotenv import load_dotenv
        load_dotenv()
        print(f"{GREEN}✓{RESET} Loaded .env file\n")
    except ImportError:
        print(f"{YELLOW}⚠{RESET} python-dotenv not installed, checking system env only\n")
    
    results: List[Tuple[str, bool, str]] = []
    
    # Define all environment variables to check
    checks = [
        # Application
        ("APP_ENV", False, False),
        ("APP_NAME", False, False),
        ("CORS_ORIGINS", True, False),
        
        # Security
        ("JWT_SECRET_KEY", True, True),
        ("JWT_ACCESS_TOKEN_MINUTES", False, False),
        
        # Database
        ("DATABASE_URL", True, True),
        ("SUPABASE_URL", True, False),
        ("SUPABASE_SERVICE_ROLE_KEY", False, True),
        
        # LiveKit
        ("LIVEKIT_URL", True, False),
        ("LIVEKIT_API_KEY", True, True),
        ("LIVEKIT_API_SECRET", True, True),
        ("LIVEKIT_AGENT_NAME", False, False),
        
        # Google Cloud / Vertex AI
        ("GOOGLE_CREDENTIALS_JSON", True, True),
        ("GOOGLE_APPLICATION_CREDENTIALS", False, False),
        ("GOOGLE_CLOUD_PROJECT", True, False),
        ("GOOGLE_CLOUD_LOCATION", False, False),
        ("GOOGLE_STT_MODEL", False, False),
        ("VERTEX_GEMINI_MODEL", True, False),
        ("VERTEX_EMBEDDING_MODEL", False, False),
        
        # Voice/TTS
        ("CARTESIA_API_KEY", True, True),
        ("CARTESIA_VOICE_ID", True, False),
        ("MISTRAL_API_KEY", True, True),
        ("MISTRAL_MODEL", True, False),
        
        # Optional integrations
        ("FAST2SMS_API_KEY", False, True),
        ("OTP_DEMO_MODE", False, False),
        ("LOG_OTP_CODES", False, False),
    ]
    
    # Run checks
    print(f"{BLUE}Checking required environment variables:{RESET}\n")
    
    for var_name, required, is_secret in checks:
        success, message = check_env_var(var_name, required, is_secret)
        results.append((var_name, success, message))
        print(f"  {message}")
    
    # Summary
    print(f"\n{BLUE}{'='*60}{RESET}")
    
    failed = [r for r in results if not r[1]]
    passed = [r for r in results if r[1]]
    
    print(f"\n{GREEN}✓ Passed:{RESET} {len(passed)}")
    print(f"{RED}✗ Failed:{RESET} {len(failed)}\n")
    
    if failed:
        print(f"{RED}Missing or invalid environment variables:{RESET}")
        for var_name, _, message in failed:
            print(f"  - {var_name}")
        print(f"\n{YELLOW}Please set these variables before deploying to Render.{RESET}")
        print(f"{YELLOW}See RENDER_DEPLOYMENT.md for details.{RESET}\n")
        sys.exit(1)
    else:
        print(f"{GREEN}All required environment variables are set!{RESET}")
        print(f"{GREEN}You're ready to deploy to Render. 🚀{RESET}\n")
        
        # Additional validation checks
        print(f"{BLUE}Additional Checks:{RESET}\n")
        
        # Check CORS origins
        cors = os.getenv("CORS_ORIGINS", "")
        if cors:
            origins = [o.strip() for o in cors.split(",")]
            app_env = os.getenv("APP_ENV", "development").lower()
            
            if app_env == "production":
                non_https = [o for o in origins if not o.startswith("https://")]
                if non_https:
                    print(f"{YELLOW}⚠{RESET} CORS_ORIGINS should use HTTPS in production:")
                    for origin in non_https:
                        print(f"    - {origin}")
                else:
                    print(f"{GREEN}✓{RESET} CORS_ORIGINS properly configured for production")
        
        # Check OTP configuration
        otp_demo = os.getenv("OTP_DEMO_MODE", "false").lower() == "true"
        fast2sms_key = os.getenv("FAST2SMS_API_KEY", "").strip()
        
        if not otp_demo and not fast2sms_key:
            print(f"{YELLOW}⚠{RESET} SMS: Either set FAST2SMS_API_KEY or enable OTP_DEMO_MODE")
        elif otp_demo:
            print(f"{YELLOW}○{RESET} SMS: OTP demo mode enabled (no real SMS)")
        else:
            print(f"{GREEN}✓{RESET} SMS: Fast2SMS configured")
        
        # Check Google credentials
        google_creds = os.getenv("GOOGLE_CREDENTIALS_JSON", "").strip()
        if google_creds:
            try:
                import json
                creds_data = json.loads(google_creds)
                if "project_id" in creds_data and "private_key" in creds_data:
                    print(f"{GREEN}✓{RESET} Google credentials JSON is valid")
                else:
                    print(f"{YELLOW}⚠{RESET} Google credentials JSON may be incomplete")
            except json.JSONDecodeError:
                print(f"{RED}✗{RESET} Google credentials JSON is invalid")
        
        print()
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
