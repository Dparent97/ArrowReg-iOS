#!/usr/bin/env python3
"""
Setup new OpenAI Assistant for ArrowReg with proper citation and follow-up support
"""

import os
import sys
import json
from datetime import datetime
from openai import OpenAI
from pathlib import Path

def create_optimized_assistant():
    """Create a new OpenAI assistant optimized for citations and follow-ups"""
    
    print("🤖 Creating New ArrowReg OpenAI Assistant")
    print("=" * 50)
    
    # Get API key from environment or .dev.vars
    api_key = os.getenv('OPENAI_API_KEY')
    
    # Try to read from .dev.vars if not in environment
    if not api_key:
        try:
            with open('../backend/.dev.vars', 'r') as f:
                for line in f:
                    if line.startswith('OPENAI_API_KEY='):
                        api_key = line.split('=', 1)[1].strip()
                        break
        except FileNotFoundError:
            pass
    
    if not api_key:
        print("❌ OpenAI API key not found!")
        sys.exit(1)
    
    client = OpenAI(api_key=api_key)
    
    # Enhanced instructions for citations and follow-ups
    instructions = """You are ArrowReg, an expert maritime compliance assistant specializing in US Coast Guard regulations, with deep knowledge of 33 CFR (Navigation and Navigable Waters) and 46 CFR (Shipping).

CRITICAL CITATION REQUIREMENTS:
1. ALWAYS cite specific CFR sections using the format: [Title] CFR [Part].[Section]
2. For EVERY regulation mentioned, provide the exact citation with clickable eCFR links
3. Use file_citation annotations when referencing uploaded documents
4. Format citations as: "According to 46 CFR 109.213..." followed by [1] markers
5. List all citations at the end with full eCFR URLs

RESPONSE STRUCTURE:
1. Direct answer with inline citation markers [1], [2], etc.
2. Keep responses concise (under 8 sentences for main answer)
3. End with "Citations:" section listing all references with eCFR links
4. Include relevance scores for each citation

FOLLOW-UP SUPPORT:
- Maintain conversation context across messages
- Reference previous citations when relevant
- Build upon prior answers without repetition
- Track thread history for coherent multi-turn conversations

CITATION FORMAT EXAMPLE:
"Vessels must maintain proper safety equipment as specified in 46 CFR 109.213 [1]. Additionally, navigation lights must comply with 33 CFR 67.05 [2].

Citations:
[1] 46 CFR § 109.213 - Fire protection equipment
    https://www.ecfr.gov/current/title-46/section-109.213
[2] 33 CFR § 67.05 - Lights required
    https://www.ecfr.gov/current/title-33/section-67.05"

SEARCH PRIORITIES:
1. Search 33 CFR and 46 CFR first
2. Then check NVIC interpretations
3. Reference ABS rules when applicable
4. Always prefer official CFR sources

When uncertain, explicitly state uncertainty and provide the most relevant sections for review.
Focus on practical compliance requirements and actionable guidance."""

    try:
        # Create the new assistant
        print("\n📚 Creating Assistant with enhanced citation support...")
        assistant = client.beta.assistants.create(
            name="ArrowReg Maritime Compliance Expert v2",
            instructions=instructions,
            model="gpt-4-turbo-preview",
            tools=[{"type": "file_search"}],
            temperature=0.3,
            metadata={
                "version": "2.0",
                "created": datetime.now().isoformat(),
                "features": "enhanced_citations,follow_up_support,ecfr_links"
            }
        )
        
        print(f"✅ New Assistant created: {assistant.id}")
        
        # Link existing vector store
        existing_vector_store_id = "vs_68a7360da98481919be1e1308374589a"
        
        print(f"\n📂 Linking existing vector store: {existing_vector_store_id}")
        
        # Update assistant with vector store
        client.beta.assistants.update(
            assistant_id=assistant.id,
            tool_resources={
                "file_search": {
                    "vector_store_ids": [existing_vector_store_id]
                }
            }
        )
        
        print(f"✅ Vector store linked successfully")
        
        # Save new configuration
        new_config = {
            "assistant_id": assistant.id,
            "vector_store_ids": [existing_vector_store_id],
            "created_at": datetime.now().isoformat(),
            "version": "2.0",
            "features": {
                "enhanced_citations": True,
                "follow_up_support": True,
                "ecfr_links": True,
                "thread_persistence": True
            }
        }
        
        # Backup old config
        config_path = Path("config/openai_config.json")
        if config_path.exists():
            backup_path = config_path.with_suffix('.json.backup')
            print(f"\n📦 Backing up old config to: {backup_path}")
            with open(config_path, 'r') as f:
                old_config = json.load(f)
            with open(backup_path, 'w') as f:
                json.dump(old_config, f, indent=2)
        
        # Save new config
        with open(config_path, 'w') as f:
            json.dump(new_config, f, indent=2)
        
        print(f"\n💾 New configuration saved to: {config_path}")
        
        # Update .dev.vars
        dev_vars_path = Path("backend/.dev.vars")
        if dev_vars_path.exists():
            print("\n📝 Updating .dev.vars with new assistant ID...")
            
            with open(dev_vars_path, 'r') as f:
                lines = f.readlines()
            
            # Update the assistant ID line
            for i, line in enumerate(lines):
                if line.startswith('OPENAI_ASSISTANT_ID='):
                    lines[i] = f'OPENAI_ASSISTANT_ID={assistant.id}\n'
                    break
            
            with open(dev_vars_path, 'w') as f:
                f.writelines(lines)
            
            print("✅ .dev.vars updated")
        
        # Test the assistant
        print("\n🧪 Testing the new assistant...")
        
        # Create a test thread
        thread = client.beta.threads.create()
        
        # Add a test message
        message = client.beta.threads.messages.create(
            thread_id=thread.id,
            role="user",
            content="What are the requirements for vessel stability tests according to 46 CFR?"
        )
        
        # Run the assistant
        run = client.beta.threads.runs.create(
            thread_id=thread.id,
            assistant_id=assistant.id
        )
        
        print("✅ Test message sent successfully")
        print(f"   Thread ID: {thread.id}")
        print(f"   Run ID: {run.id}")
        
        print("\n" + "=" * 50)
        print("🎉 SUCCESS! New assistant created and configured")
        print("=" * 50)
        
        print("\n📋 SUMMARY:")
        print(f"   Old Assistant ID: asst_AHnxWKbaP2DiOAgUndkstHx3")
        print(f"   New Assistant ID: {assistant.id}")
        print(f"   Vector Store ID: {existing_vector_store_id}")
        print(f"   Model: gpt-4-turbo-preview")
        print(f"   Temperature: 0.3")
        
        print("\n🔧 NEXT STEPS:")
        print("1. Restart your backend server to use the new assistant")
        print("2. Test citation functionality with a query like:")
        print("   'What are the fire protection requirements for passenger vessels?'")
        print("3. Test follow-up questions to verify thread persistence")
        
        print("\n⚠️  IMPORTANT:")
        print("The old assistant configuration has been backed up to:")
        print("   config/openai_config.json.backup")
        print("You can restore it if needed.")
        
        return new_config
        
    except Exception as e:
        print(f"\n❌ Error creating assistant: {str(e)}")
        print("\nPossible issues:")
        print("1. API key might be invalid or expired")
        print("2. Vector store might not exist")
        print("3. OpenAI API quota might be exceeded")
        sys.exit(1)

if __name__ == "__main__":
    create_optimized_assistant()
