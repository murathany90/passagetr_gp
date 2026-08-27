import json
from pathlib import Path
r=Path(__file__).parent
f=sorted((r/'items').glob('*.json'));assert len(f)==100
s=q=0
for p in f:
 x=json.loads(p.read_text(encoding='utf-8'));assert len(x['sentences'])==15;assert len(x['questions'])==5
 assert [z['index'] for z in x['sentences']]==list(range(1,16))
 for z in x['questions']: assert len(z['options_en'])==4 and len(z['options_tr'])==4 and z['evidence_sentence_indexes']
 s+=15;q+=5
assert s==1500 and q==500
print('PASS readings=100 sentence_pairs=1500 questions=500')
