---
description: Show total token usage and estimated cost across all sessions in this project
---

# Total Token Usage

Calculate and display total token usage across all Claude Code sessions for the current project.

## Your Task

1. Find all session transcript JSONL files in the project's Claude directory at `~/.claude/projects/` matching the current working directory path (replace `/` with `-` in the path, e.g. `-Users-hassan-Documents-claude-athanframework`)

2. Run the following Python script via Bash to parse all session files and sum token usage:

```
python3 -c "
import json, glob, os

# Build the project key from cwd
cwd = os.getcwd()
project_key = cwd.replace('/', '-')
pattern = os.path.expanduser(f'~/.claude/projects/{project_key}/*.jsonl')
files = sorted(glob.glob(pattern))

if not files:
    print('No session files found for this project.')
    exit()

total_input = 0
total_output = 0
total_cache_create = 0
total_cache_read = 0
session_count = 0

for f in files:
    s_in = s_out = s_cc = s_cr = 0
    found = False
    with open(f) as fh:
        for line in fh:
            line = line.strip()
            if not line or 'input_tokens' not in line:
                continue
            try:
                obj = json.loads(line)
                def find_usage(d):
                    if isinstance(d, dict):
                        if 'input_tokens' in d:
                            return d
                        for v in d.values():
                            r = find_usage(v)
                            if r:
                                return r
                    elif isinstance(d, list):
                        for v in d:
                            r = find_usage(v)
                            if r:
                                return r
                    return None
                usage = find_usage(obj)
                if usage and isinstance(usage, dict):
                    found = True
                    s_in += usage.get('input_tokens', 0)
                    s_out += usage.get('output_tokens', 0)
                    s_cc += usage.get('cache_creation_input_tokens', 0)
                    s_cr += usage.get('cache_read_input_tokens', 0)
            except:
                pass

    if found:
        session_count += 1
        total_input += s_in
        total_output += s_out
        total_cache_create += s_cc
        total_cache_read += s_cr
        name = os.path.basename(f)[:16]
        s_total = s_in + s_out + s_cc + s_cr
        print(f'  {name}..  in:{s_in:>9,}  out:{s_out:>8,}  c_create:{s_cc:>10,}  c_read:{s_cr:>10,}  total:{s_total:>11,}')

grand = total_input + total_output + total_cache_create + total_cache_read
print()
print(f'Sessions:           {session_count}')
print(f'Input tokens:       {total_input:>12,}')
print(f'Output tokens:      {total_output:>12,}')
print(f'Cache creation:     {total_cache_create:>12,}')
print(f'Cache read:         {total_cache_read:>12,}')
print(f'────────────────────────────────────')
print(f'Grand total:        {grand:>12,}')
print()
ic = (total_input / 1e6) * 15
oc = (total_output / 1e6) * 75
ccc = (total_cache_create / 1e6) * 18.75
crc = (total_cache_read / 1e6) * 1.50
tc = ic + oc + ccc + crc
print(f'Cost estimate (Opus \$15/\$75 in/out, \$18.75/\$1.50 cache):')
print(f'  Input:            \${ic:>8.2f}')
print(f'  Output:           \${oc:>8.2f}')
print(f'  Cache creation:   \${ccc:>8.2f}')
print(f'  Cache read:       \${crc:>8.2f}')
print(f'  ──────────────────────────')
print(f'  Estimated total:  \${tc:>8.2f}')
print()
print('Note: On Max plan (\$100/\$200 mo), tokens are included — cost is for API/pay-per-token only.')
"
```

3. Present the output to the user as-is. Add a brief note that cache reads (~96% of usage) are the cheapest token type at $1.50/M vs $15/M for fresh input.
