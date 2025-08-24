#!/usr/bin/env python3
"""
Sample Data Ingestion Script for ArrowReg
Uploads sample regulation documents to OpenAI vector stores

Usage:
    export OPENAI_API_KEY="sk-your-key-here"
    python3 ingest-sample-data.py
"""

import os
import json
import sys
import time
from pathlib import Path
from openai import OpenAI

def load_config():
    """Load OpenAI configuration"""
    config_file = Path("config/openai_config.json")
    if not config_file.exists():
        print("❌ OpenAI configuration not found. Run setup-openai.py first.")
        sys.exit(1)
    
    with open(config_file, 'r') as f:
        return json.load(f)

def create_sample_cfr_documents():
    """Create sample CFR document content for testing"""
    sample_docs = [
        {
            "filename": "46_cfr_109_fire_detection.txt",
            "title": "46 CFR 109.213 - Fire detection systems",
            "content": """46 CFR 109.213 - Fire detection systems

(a) General requirements. Each OSV must be fitted with an automatic fire detection and alarm system that complies with the requirements of this section.

(b) Coverage areas. The fire detection system must provide coverage for:
(1) All machinery spaces
(2) All accommodation spaces
(3) Service spaces presenting a fire risk
(4) Control stations
(5) Cargo pump-rooms

(c) Detection methods. The system must use appropriate detection methods including:
(1) Smoke detection for accommodation and control spaces
(2) Heat detection for machinery spaces
(3) Flame detection where appropriate for high-risk areas

(d) Alarm requirements. The fire detection system must:
(1) Provide audible and visual alarms at the fire control station
(2) Automatically transmit alarms to the navigation bridge
(3) Include means for silencing audible alarms
(4) Provide indication of the specific zone in alarm

(e) Power supply. The system must have:
(1) A primary power supply from the vessel's main source
(2) An emergency power supply capable of operating the system for 18 hours
(3) Automatic transfer between power supplies

(f) Testing and maintenance. The system must:
(1) Include provisions for testing all components
(2) Be tested weekly when the vessel is in service
(3) Be maintained according to manufacturer's instructions"""
        },
        {
            "filename": "33_cfr_151_oil_discharge.txt", 
            "title": "33 CFR 151.10 - Oil discharge prohibitions",
            "content": """33 CFR 151.10 - Discharge of oil prohibited

(a) Except as provided in paragraphs (b) and (c) of this section, the discharge of oil or oily waste into the navigable waters of the United States or the waters of the contiguous zone is prohibited.

(b) This section does not apply to:
(1) The discharge of clean ballast water or segregated ballast water
(2) The discharge of oil or oily waste from a vessel for the purpose of securing the safety of the vessel or preventing damage to the vessel or its cargo
(3) The discharge of oily waste from properly functioning machinery space bilges of a vessel, provided that:
    (i) The oil content of the discharge does not exceed 15 parts per million
    (ii) The vessel has in operation oily-water separating equipment
    (iii) The discharge is made while the vessel is proceeding en route

(c) Areas of application:
(1) This section applies to all navigable waters of the United States
(2) This section applies to all waters of the contiguous zone
(3) Special areas may have additional restrictions

(d) Penalties. Violations of this section may result in:
(1) Civil penalties up to $40,000 per day
(2) Criminal penalties including fines and imprisonment
(3) Vessel detention until corrective action is taken

(e) Reporting requirements:
(1) Any discharge must be reported immediately to the National Response Center
(2) A written report must be submitted within 30 days
(3) Records of all discharges must be maintained for 3 years"""
        },
        {
            "filename": "46_cfr_199_lifesaving.txt",
            "title": "46 CFR 199 - Lifesaving equipment requirements",
            "content": """46 CFR 199 - Lifesaving systems and arrangements

§199.10 General requirements for lifesaving equipment

(a) Purpose. This subchapter prescribes requirements for lifesaving equipment and arrangements on vessels to which it applies.

(b) Objective. The objective is to ensure that vessels carry adequate lifesaving equipment to:
(1) Provide for the safe abandonment of the vessel
(2) Provide for survival until rescue
(3) Provide for rescue operations

§199.50 Survival craft requirements

(a) General. Each vessel must carry:
(1) Lifeboats sufficient for 100% of persons on board, or
(2) Life rafts sufficient for 100% of persons on board, or
(3) A combination of lifeboats and life rafts sufficient for 100% of persons on board

(b) Additional requirements:
(1) Life rafts must be automatically inflatable
(2) Life rafts must be equipped with emergency equipment
(3) All survival craft must be approved by the Coast Guard

§199.70 Personal lifesaving appliances

(a) Life jackets. The vessel must carry:
(1) A Coast Guard approved life jacket for each person on board
(2) Additional life jackets equal to 5% of persons on board
(3) Life jackets suitable for children if children are carried

(b) Immersion suits:
(1) Required for each person on board vessels operating in cold water
(2) Must be Coast Guard approved
(3) Must be properly sized and maintained

(c) Life rings:
(1) Not less than 8 life rings must be carried
(2) At least 2 must be equipped with self-igniting lights
(3) At least 2 must be equipped with smoke signals"""
        }
    ]
    
    # Create data directory
    data_dir = Path("data/samples")
    data_dir.mkdir(parents=True, exist_ok=True)
    
    created_files = []
    for doc in sample_docs:
        file_path = data_dir / doc["filename"]
        with open(file_path, 'w') as f:
            f.write(doc["content"])
        created_files.append(file_path)
        print(f"✅ Created sample document: {file_path}")
    
    return created_files

def upload_documents_to_vector_stores(client, config, document_files):
    """Upload documents to appropriate vector stores"""
    print("📤 Uploading documents to vector stores...")
    
    vector_stores = {vs['name']: vs['id'] for vs in config['vector_stores']}
    
    uploaded_files = []
    
    for doc_path in document_files:
        try:
            print(f"   Uploading: {doc_path.name}")
            
            # Upload file to OpenAI
            with open(doc_path, 'rb') as f:
                file_obj = client.files.create(
                    file=f,
                    purpose='assistants'
                )
            
            print(f"   ✅ File uploaded: {file_obj.id}")
            
            # Determine appropriate vector store based on filename
            if "46_cfr" in doc_path.name:
                store_name = "CFR Title 46 - Shipping"
            elif "33_cfr" in doc_path.name:
                store_name = "CFR Title 33 - Navigation and Navigable Waters"
            else:
                store_name = list(vector_stores.keys())[0]  # Default to first store
            
            if store_name in vector_stores:
                store_id = vector_stores[store_name]
                
                # Add file to vector store
                client.beta.vector_stores.files.create(
                    vector_store_id=store_id,
                    file_id=file_obj.id
                )
                
                print(f"   ✅ Added to vector store: {store_name}")
                uploaded_files.append({
                    'file_id': file_obj.id,
                    'filename': doc_path.name,
                    'vector_store': store_name
                })
            
            # Small delay to avoid rate limiting
            time.sleep(1)
            
        except Exception as e:
            print(f"   ❌ Failed to upload {doc_path.name}: {str(e)}")
    
    return uploaded_files

def test_assistant_query(client, assistant_id):
    """Test the assistant with a sample query"""
    print("🧪 Testing assistant with sample query...")
    
    try:
        # Create a test thread
        thread = client.beta.threads.create()
        
        # Add a message
        message = client.beta.threads.messages.create(
            thread_id=thread.id,
            role="user",
            content="What are the fire detection requirements for OSVs according to 46 CFR 109?"
        )
        
        # Run the assistant
        run = client.beta.threads.runs.create(
            thread_id=thread.id,
            assistant_id=assistant_id,
            instructions="Provide a concise answer with specific regulation citations."
        )
        
        # Wait for completion
        max_attempts = 30
        attempts = 0
        
        while attempts < max_attempts:
            run_status = client.beta.threads.runs.retrieve(
                thread_id=thread.id,
                run_id=run.id
            )
            
            if run_status.status == 'completed':
                # Get the response
                messages = client.beta.threads.messages.list(
                    thread_id=thread.id
                )
                
                assistant_message = messages.data[0].content[0].text.value
                print("✅ Assistant test successful!")
                print(f"Response preview: {assistant_message[:200]}...")
                return True
                
            elif run_status.status == 'failed':
                print(f"❌ Assistant test failed: {run_status.last_error}")
                return False
            
            time.sleep(2)
            attempts += 1
        
        print("❌ Assistant test timed out")
        return False
        
    except Exception as e:
        print(f"❌ Assistant test failed: {str(e)}")
        return False

def main():
    print("📚 Ingesting sample regulation data...")
    
    # Check prerequisites
    api_key = os.getenv('OPENAI_API_KEY')
    if not api_key:
        print("❌ Error: OPENAI_API_KEY environment variable not set")
        sys.exit(1)
    
    client = OpenAI(api_key=api_key)
    
    # Load configuration
    config = load_config()
    print(f"✅ Loaded configuration for assistant: {config['assistant_id']}")
    
    try:
        # Create sample documents
        print("📝 Creating sample CFR documents...")
        document_files = create_sample_cfr_documents()
        
        # Upload documents to vector stores
        uploaded_files = upload_documents_to_vector_stores(client, config, document_files)
        
        print(f"\n✅ Successfully uploaded {len(uploaded_files)} documents")
        
        # Test assistant
        if test_assistant_query(client, config['assistant_id']):
            print("\n🎉 Sample data ingestion complete!")
            print("   The assistant is ready to answer maritime compliance questions")
            print("   Try testing with queries like:")
            print("   - 'What are fire detection requirements for OSVs?'")
            print("   - 'Tell me about oil discharge regulations'")
            print("   - 'What lifesaving equipment is required?'")
        else:
            print("\n⚠️  Documents uploaded but assistant test failed")
            print("   Check the OpenAI dashboard for any issues")
        
        return True
        
    except Exception as e:
        print(f"❌ Data ingestion failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()