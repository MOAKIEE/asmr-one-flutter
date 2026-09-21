import json, urllib.request, sys, collections, time

def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    return json.loads(urllib.request.urlopen(req, timeout=30).read().decode())

tags, cnt = {}, collections.Counter()
combos = [('dl_count','desc'),('create_date','desc'),('rate_average_2dp','desc'),
          ('review_count','desc'),('release','desc'),('price','desc')]
for order, sort in combos:
    for page in range(1, 7):
        try:
            d = get(f"https://api.asmr.one/api/works?page={page}&pageSize=100&order={order}&sort={sort}")
        except Exception as e:
            continue
        for w in d.get('works') or []:
            for t in w.get('tags') or []:
                tid = t.get('id')
                if tid is None: continue
                cnt[tid] += 1
                if tid not in tags:
                    i = t.get('i18n') or {}
                    tags[tid] = {
                        'ja': (i.get('ja-jp') or {}).get('name') or t.get('name') or '',
                        'zh': (i.get('zh-cn') or {}).get('name') or t.get('name') or '',
                        'en': (i.get('en-us') or {}).get('name') or t.get('name') or '',
                    }
        time.sleep(0.05)

rows = []
for tid, n in cnt.most_common(400):
    if tid in tags:
        t = tags[tid]
        rows.append({'id': tid, 'zh': t['zh'], 'ja': t['ja'], 'en': t['en'], 'n': n})

with open('tags_raw.json', 'w', encoding='utf-8') as f:
    json.dump(rows, f, ensure_ascii=False, indent=1)
print('TOTAL', len(rows))
