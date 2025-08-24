#!/usr/bin/env python3
"""
OpenAI Assistant Setup Script for ArrowReg
Creates the AI assistant and vector stores for maritime compliance

Usage:
    export OPENAI_API_KEY="sk-your-key-here"
    python3 setup-openai.py
"""

import os
import json
import sys
from pathlib import Path
from openai import OpenAI

# Configuration
ASSISTANT_NAME = "ArrowReg Maritime Compliance Assistant"
ASSISTANT_INSTRUCTIONS = """
You are ArrowReg, a maritime compliance expert specializing in U.S. Coast Guard regulations, 
CFR Title 33 & 46, ABS rules, and international maritime law.

Your role:
- Provide accurate, authoritative answers about maritime regulations
- Cite specific CFR sections and regulations
- Explain compliance requirements clearly
- Consider vessel type, route, and operational context
- Integrate weather conditions with regulatory requirements when relevant
- Focus on practical implementation of regulations

Guidelines:
- Always cite sources with specific regulation numbers
- Be concise but thorough
- Consider safety implications
- Mention when professional maritime counsel should be consulted
- Stay current with regulatory updates
"""

VECTOR_STORE_CONFIGS = [
    {
        "name": "CFR Title 33 - Navigation and Navigable Waters",
        "description": "Complete CFR Title 33 covering navigation rules, port regulations, and environmental compliance",
        "file_search": True
    },
    {
        "name": "CFR Title 46 - Shipping", 
        "description": "Complete CFR Title 46 covering vessel construction, equipment, manning, and operation",
        "file_search": True
    },
    {
        "name": "ABS Rules and Guides",
        "description": "American Bureau of Shipping classification rules and guidance notes",
        "file_search": True
    },
    {
        "name": "NVIC and Maritime Safety Alerts",
        "description": "Navigation and Vessel Inspection Circulars and safety alerts",
        "file_search": True
    }
]

def check_api_key():
    """Verify OpenAI API key is available"""
    api_key = os.getenv('OPENAI_API_KEY')
    if not api_key:
        print("❌ Error: OPENAI_API_KEY environment variable not set")
        print("Please set your API key: export OPENAI_API_KEY='sk-your-key-here'")
        sys.exit(1)
    
    if not api_key.startswith('sk-'):
        print("❌ Error: Invalid OpenAI API key format")
        sys.exit(1)
    
    return api_key

def create_vector_stores(client):
    """Create vector stores for different regulation types"""
    print("📚 Creating vector stores...")
    vector_stores = []
    
    for config in VECTOR_STORE_CONFIGS:
        try:
            print(f"   Creating: {config['name']}")
            
            vector_store = client.beta.vector_stores.create(
                name=config['name'],
                file_search=config.get('file_search', True)
            )
            
            vector_stores.append({
                'id': vector_store.id,
                'name': config['name'],
                'description': config['description']
            })
            
            print(f"   ✅ Created vector store: {vector_store.id}")
            
        except Exception as e:
            print(f"   ❌ Failed to create {config['name']}: {str(e)}")
    
    return vector_stores

def create_assistant(client, vector_store_ids):
    """Create the maritime compliance assistant"""
    print("🤖 Creating OpenAI assistant...")
    
    try:
        # Prepare tools
        tools = [
            {"type": "file_search"},
            {
                "type": "function",
                "function": {
                    "name": "get_weather_conditions",
                    "description": "Get current maritime weather conditions for regulatory context",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "latitude": {"type": "number", "description": "Latitude coordinate"},
                            "longitude": {"type": "number", "description": "Longitude coordinate"},
                            "vessel_type": {"type": "string", "description": "Type of vessel (OSV, tanker, cargo, etc.)"}
                        },
                        "required": ["latitude", "longitude"]
                    }
                }
            }
        ]
        
        # Create tool resources
        tool_resources = {}
        if vector_store_ids:
            tool_resources["file_search"] = {
                "vector_store_ids": vector_store_ids
            }
        
        assistant = client.beta.assistants.create(
            name=ASSISTANT_NAME,
            instructions=ASSISTANT_INSTRUCTIONS,
            model="gpt-4-turbo-preview",
            tools=tools,
            tool_resources=tool_resources,
            temperature=0.1  # Lower temperature for more factual responses
        )
        
        print(f"✅ Created assistant: {assistant.id}")
        return assistant
        
    except Exception as e:
        print(f"❌ Failed to create assistant: {str(e)}")
        return None

def save_configuration(assistant_id, vector_stores):
    """Save configuration to files"""
    print("💾 Saving configuration...")
    
    # Create config directory
    config_dir = Path("config")
    config_dir.mkdir(exist_ok=True)
    
    # Save OpenAI configuration
    config = {
        "assistant_id": assistant_id,
        "vector_stores": vector_stores,
        "created_at": str(Path(__file__).stat().st_mtime),
        "model": "gpt-4-turbo-preview"
    }
    
    config_file = config_dir / "openai_config.json"
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print(f"✅ Saved configuration to {config_file}")
    
    # Update backend .dev.vars
    backend_dir = Path("backend")
    if backend_dir.exists():
        dev_vars_file = backend_dir / ".dev.vars"
        
        # Read existing vars
        existing_vars = {}
        if dev_vars_file.exists():
            with open(dev_vars_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        existing_vars[key] = value
        
        # Update with new values
        existing_vars['OPENAI_ASSISTANT_ID'] = assistant_id
        existing_vars['VECTOR_STORE_IDS'] = ','.join([vs['id'] for vs in vector_stores])
        
        # Write updated vars
        with open(dev_vars_file, 'w') as f:
            f.write("# ArrowReg Backend Development Environment\n")
            f.write("# This file contains development environment variables for Cloudflare Workers\n\n")
            
            for key, value in existing_vars.items():
                f.write(f"{key}={value}\n")
        
        print(f"✅ Updated {dev_vars_file}")
    
    return config

def main():
    print("🚀 Setting up OpenAI for ArrowReg...")
    
    # Check prerequisites
    api_key = check_api_key()
    client = OpenAI(api_key=api_key)
    
    try:
        # Test API connection
        print("🔌 Testing OpenAI API connection...")
        models = client.models.list()
        print("✅ OpenAI API connection successful")
        
        # Create vector stores
        vector_stores = create_vector_stores(client)
        
        if not vector_stores:
            print("⚠️  No vector stores created, but continuing with assistant...")
        
        # Create assistant
        vector_store_ids = [vs['id'] for vs in vector_stores]
        assistant = create_assistant(client, vector_store_ids)
        
        if not assistant:
            print("❌ Failed to create assistant")
            sys.exit(1)
        
        # Save configuration
        config = save_configuration(assistant.id, vector_stores)
        
        print("\n🎉 OpenAI setup complete!")
        print(f"   Assistant ID: {assistant.id}")
        print(f"   Vector Stores: {len(vector_stores)}")
        print(f"   Config saved: config/openai_config.json")
        
        print("\n📋 Next steps:")
        print("1. Upload regulation documents to vector stores using OpenAI dashboard")
        print("2. Test the assistant with sample queries")
        print("3. Start the backend server: cd backend && npm run dev")
        
        return config
        
    except Exception as e:
        print(f"❌ Setup failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()