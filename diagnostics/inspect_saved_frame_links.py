import json
import sqlite3
import sys
from pathlib import Path

with sqlite3.connect(Path(sys.argv[1]).resolve().as_uri() + '?mode=ro', uri=True) as db:
    for item_id, raw in db.execute('SELECT id, partitions_json FROM Commandes_details ORDER BY id DESC LIMIT 150'):
        try:
            data = json.loads(raw or '{}')
        except (ValueError, TypeError):
            continue
        if 'bs90' not in json.dumps(data).lower().replace(' ', ''):
            continue
        result = {'item_id': item_id}
        for key in ('systemMode', 'seriesId', 'seriesName', 'slidingSeriesId', 'slidingSeriesName'):
            result[key] = data.get(key)
        for key in ('frameOverride', 'slidingFrameOverride'):
            value = data.get(key) or {}
            result[key] = {field: value.get(field) for field in ('id', 'code', 'series_id')}
        print(json.dumps(result, ensure_ascii=False))
