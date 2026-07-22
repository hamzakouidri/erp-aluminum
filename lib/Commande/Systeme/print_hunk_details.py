with open("full_diff.txt", "r", encoding="utf-8") as f:
    lines = f.readlines()

out_lines = []
in_unbalanced_hunk = False

for line in lines:
    if line.startswith("@@"):
        if "@@ -9122" in line:
            in_unbalanced_hunk = True
        else:
            in_unbalanced_hunk = False
    
    if in_unbalanced_hunk:
        out_lines.append(line)

with open("unbalanced_hunk.txt", "w", encoding="utf-8") as f:
    f.writelines(out_lines)

print("Wrote unbalanced hunk diff. Total lines:", len(out_lines))
