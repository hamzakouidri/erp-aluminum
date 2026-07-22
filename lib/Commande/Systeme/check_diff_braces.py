with open("full_diff.txt", "r", encoding="utf-8") as f:
    lines = f.readlines()

current_hunk = None
hunk_lines = []

for line in lines:
    if line.startswith("@@"):
        if current_hunk:
            # Process hunk
            del_braces = 0
            add_braces = 0
            for hl in hunk_lines:
                if hl.startswith("-") and not hl.startswith("---"):
                    del_braces += hl.count("{") - hl.count("}")
                elif hl.startswith("+") and not hl.startswith("+++"):
                    add_braces += hl.count("{") - hl.count("}")
            diff_balance = add_braces - del_braces
            if diff_balance != 0:
                print(f"Hunk {current_hunk} is UNBALANCED! Balance diff: {diff_balance}")
                for hl in hunk_lines:
                    if hl.startswith("+") or hl.startswith("-"):
                        print(hl.strip())
                print("="*40)
        current_hunk = line.strip()
        hunk_lines = []
    else:
        hunk_lines.append(line)

# Process last hunk
if current_hunk:
    del_braces = 0
    add_braces = 0
    for hl in hunk_lines:
        if hl.startswith("-") and not hl.startswith("---"):
            del_braces += hl.count("{") - hl.count("}")
        elif hl.startswith("+") and not hl.startswith("+++"):
            add_braces += hl.count("{") - hl.count("}")
    diff_balance = add_braces - del_braces
    if diff_balance != 0:
        print(f"Hunk {current_hunk} is UNBALANCED! Balance diff: {diff_balance}")
        for hl in hunk_lines:
            if hl.startswith("+") or hl.startswith("-"):
                print(hl.strip())
        print("="*40)
