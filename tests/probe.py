"""CI-only local probe. Does not print credentials or account data."""
import json
from pathlib import Path
import sys
import urllib.error
import urllib.request

directory=Path(sys.argv[1]);action=sys.argv[2]
keys=json.loads((directory/'data/auth.json').read_text())
def call(path,key,method='GET'):
    req=urllib.request.Request('http://127.0.0.1:19610'+path,
        data=b'{}' if method=='POST' else None,
        headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'},method=method)
    try:
        with urllib.request.urlopen(req,timeout=5) as r:return r.status,json.load(r)
    except urllib.error.HTTPError as e:return e.code,{}

assert call('/admin/accounts',keys['api'])[0]==403
assert call('/admin/accounts',keys['admin'])[0]==200
if action=='rotate':
    code,result=call('/admin/apikey/rotate',keys['admin'],'POST')
    assert code==200
    assert call('/v1/models',keys['api'])[0]==401
    assert call('/v1/models',result['api_key'])[0]==200
    assert json.loads((directory/'data/auth.json').read_text())['api']==result['api_key']
    (directory/'ci-rotated-key').write_text(result['api_key'])
else:
    assert keys['api']==(directory/'ci-rotated-key').read_text()
    assert call('/v1/models',keys['api'])[0]==200
print('PASS local API boundary and persistent credentials')
