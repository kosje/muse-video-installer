import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('render',ROOT/'deploy/render.py')
render=importlib.util.module_from_spec(spec);spec.loader.exec_module(render)


class DeploymentTests(unittest.TestCase):
    def test_private_deployment(self):
        with tempfile.TemporaryDirectory() as tmp:
            render.render(ROOT/'release.json','/opt/mvw-secure','18610','',tmp)
            d=json.loads((Path(tmp)/'compose.yml').read_text())
            self.assertEqual(set(d['services']),{'api'})
            api=d['services']['api']
            self.assertEqual(api['ports'],['127.0.0.1:18610:18610'])
            self.assertEqual(api['user'],'10001:10001')
            self.assertTrue(api['read_only'])
            self.assertEqual(api['cap_drop'],['ALL'])
            self.assertNotIn('MUSE2API_KEY',api['environment'])
            self.assertEqual(api['volumes'][0]['target'],'/app/data')
            self.assertNotIn('network_mode',api)
            self.assertNotIn('docker.sock',json.dumps(d))

    def test_https_frontend_and_api_same_origin(self):
        with tempfile.TemporaryDirectory() as tmp:
            render.render(ROOT/'release.json','/srv/muse','19610','video.example.com',tmp)
            d=json.loads((Path(tmp)/'compose.yml').read_text())
            self.assertEqual(d['services']['api']['ports'],['127.0.0.1:19610:18610'])
            self.assertEqual(d['services']['api']['environment']['MUSE2API_PUBLIC_BASE'],'https://video.example.com')
            self.assertIn('@sha256:',d['services']['proxy']['image'])
            c=(Path(tmp)/'Caddyfile').read_text()
            self.assertIn('reverse_proxy api:18610',c)
            self.assertIn('admin off',c)
            self.assertNotIn('file_server',c)

    def test_invalid_input(self):
        for directory in ['/','/opt','/opt/..','/opt/a/b',"/opt/a';id",'/home/test','/opt/test\nExecStart=x']:
            with self.subTest(directory=directory), self.assertRaises(ValueError): render.validate(directory,'18610','')
        for domain in ['example.com\n{','https://example.com','*.example.com','example.com:443','foo/bar','EXAMPLE.com']:
            with self.subTest(domain=domain), self.assertRaises(ValueError): render.validate('/opt/muse','18610',domain)
        for port in ['0','80','65536','1;id','abc','18610\n']:
            with self.subTest(port=port), self.assertRaises(ValueError): render.validate('/opt/muse',port,'')

    def test_no_symbolic_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest=Path(tmp)/'bad.json'
            d=json.loads((ROOT/'release.json').read_text());d['backend_commit']='main'
            manifest.write_text(json.dumps(d))
            with self.assertRaises(ValueError): render.render(manifest,'/opt/muse','18610','',tmp)


if __name__=='__main__':unittest.main()
