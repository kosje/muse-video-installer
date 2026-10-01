"""Offline transport and credential tests; never launches a browser."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('helper',Path(__file__).with_name('get_muse_cookie.py'))
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)

class HelperTests(unittest.TestCase):
    def test_transport(self):
        for u in ['https://video.example.com','http://127.0.0.1:18610','http://[::1]:18610']:
            helper.validate_transport(u)
        for u in ['http://video.example.com','http://localhost.evil.example','file:///etc/passwd','https://user:pass@example.com','https://example.com/?key=x']:
            with self.subTest(url=u),self.assertRaises(RuntimeError):helper.validate_transport(u)
    def test_credentials_not_saved(self):
        with tempfile.TemporaryDirectory() as tmp:
            helper.CONF_PATH=str(Path(tmp)/'config.json')
            Path(helper.CONF_PATH).write_text(json.dumps({'key':'old-secret'}))
            helper.save_conf(base='https://example.com',key='new-secret')
            self.assertNotIn('key',json.loads(Path(helper.CONF_PATH).read_text()))
    def test_cookie_domain_boundary(self):
        class WS:
            def call(self,*a,**k):return {'cookies':[{'domain':'muse.ai.evil.example','name':'evil','value':'secret'},{'domain':'.muse.ai','name':'good','value':'valid'}]}
        self.assertEqual(set(helper.read_cookies(WS())),{'good'})
    def test_redirects_rejected(self):
        with self.assertRaises(RuntimeError):helper.NoRedirect().redirect_request(None,None,302,None,None,'https://evil.example')

if __name__=='__main__':unittest.main()
