import urllib.request
import json

url = "https://firestore.googleapis.com/v1/projects/erp-aluminum-701f9/databases/(default)/documents/workshops/gpFPvIMjazb23WXedc8ClD4ggXY2/backups/latest/chunks"

try:
    with urllib.request.urlopen(url) as response:
        html = response.read().decode('utf-8')
        data = json.loads(html)
        print("--- FIREBASE CHUNKS ---")
        documents = data.get('documents', [])
        print(f"Total chunks in Firestore: {len(documents)}")
        for doc in documents:
            name = doc.get('name', '')
            doc_id = name.split('/')[-1]
            fields = doc.get('fields', {})
            table = fields.get('table', {}).get('stringValue', 'Unknown')
            print(f"  Chunk ID: {doc_id} => Table: {table}")
        print("-----------------------")
except Exception as e:
    print(f"Error querying Firestore REST API: {e}")
