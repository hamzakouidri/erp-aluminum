import subprocess
res = subprocess.run(["git", "diff", "show_system_francais.dart"], capture_output=True)
with open("full_diff.txt", "w", encoding="utf-8") as f:
    f.write(res.stdout.decode("utf-8", errors="ignore"))
print("Done! Diff length:", len(res.stdout))
