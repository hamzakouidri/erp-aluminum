path_log = r'C:\Users\hp\.gemini\antigravity\brain\2e53df2d-4f4a-4c8f-9b10-9091249fb344\.system_generated\logs\transcript.jsonl'
path_out = r'C:\Users\hp\Desktop\Noraleur\erp-aluminum-main\.gemini\antigravity\brain\2e53df2d-4f4a-4c8f-9b10-9091249fb344\scratch\search_transcript_output.txt'

with open(path_log, 'r', encoding='utf-8') as f, open(path_out, 'w', encoding='utf-8') as out:
    for line in f:
        if 'PdfInvoiceApi' in line or 'font' in line.lower() or 'spinner' in line.lower():
            out.write(line + '\n')
print("Done searching.")
