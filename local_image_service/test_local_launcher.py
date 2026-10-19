"""Only fake credentials in isolated temp files; never use the project's config."""
import base64
import concurrent.futures
import ctypes
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from private_config import ConfigError, PrivateConfig
from launcher_core import Controller, LauncherError, LocalClient, SingleInstance
from server import Engine, LocalServer, RequestError, UpstreamFailure
from test_server import payload

FAKE = 'offline-fixture-not-a-real-key'


class PrivateConfigTests(unittest.TestCase):
    def test_import_and_constructor_do_not_read_private_file(self):
        with patch.object(Path,'read_text',side_effect=AssertionError('No file reads')):
            PrivateConfig()

    def test_fake_key_can_be_loaded_only_from_isolated_test_file(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'api_key.local.json'
            p.write_text(json.dumps({'api_key':FAKE}),encoding='utf-8')
            self.assertEqual(PrivateConfig(p).read_key(),FAKE)
            self.assertEqual(json.loads(p.read_text())['api_key'],FAKE)

    def test_missing_and_invalid_configs_never_echo_contents(self):
        values=[{'api_key':''},{'api_key':FAKE,'other':'field'},[],{'api_key':'bad\n'+FAKE},{'api_key':' '},{'api_key':42}]
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'api_key.local.json'
            with self.assertRaises(ConfigError) as e:PrivateConfig(p).read_key()
            self.assertEqual(str(e.exception),'private_config_missing')
            for value in values:
                p.write_text(json.dumps(value),encoding='utf-8')
                with self.assertRaises(ConfigError) as e:PrivateConfig(p).read_key()
                self.assertNotIn(FAKE,str(e.exception))
            p.write_text('{"api_key":"'+FAKE+'"',encoding='utf-8')
            with self.assertRaises(ConfigError) as e:PrivateConfig(p).read_key()
            self.assertEqual(str(e.exception),'private_config_invalid')


class RetryTests(unittest.TestCase):
    def setUp(self):
        self.engine=Engine(mode='stub')
        self.engine.mode,self.engine.unit_price_fen='official',12
        self.calls=0
        def upstream(*_):
            self.calls+=1
            if self.calls==1:raise UpstreamFailure('network_timeout')
            return payload()['image']
        self.engine._official=upstream

    def tearDown(self):self.engine.close()

    def first_failure(self):
        with self.assertRaises(RequestError):self.engine.generate(payload())

    def retry(self,request_id='retry-1'):
        return self.engine.retry({'request_id':'test-1','retry_request_id':request_id,'confirm_new_charge':True})

    def test_default_allows_multiple_user_requests_without_restarting(self):
        self.engine._official=lambda *_:payload()['image']
        self.engine.generate(payload())
        self.engine.generate(payload(prompt='second drawing',request_id='second'))
        self.assertEqual(self.engine.audit()['real_calls'],2)
        self.assertIsNone(self.engine.audit()['max_calls'])

    def test_failure_is_never_retried_by_generate_or_status(self):
        self.first_failure()
        with self.assertRaises(RequestError) as e:self.engine.generate(payload(request_id='repeat-click'))
        self.engine.audit();self.engine.list_operations()
        self.assertEqual(self.calls,1)
        self.assertEqual(e.exception.code,'outcome_unknown')

    def test_retry_requires_explicit_true_and_distinct_operation_id(self):
        self.first_failure()
        for request in [{},{'request_id':'test-1','retry_request_id':'next','confirm_new_charge':False},{'request_id':'test-1','retry_request_id':'next','confirm_new_charge':1},{'request_id':'test-1','retry_request_id':'test-1','confirm_new_charge':True}]:
            with self.assertRaises(RequestError):self.engine.retry(request)
        self.assertEqual(self.calls,1)

    def test_explicit_retry_preserves_first_failure_and_returns_one_result(self):
        self.first_failure()
        result=self.retry()
        self.assertEqual(result['source'],'volcengine_official')
        history=self.engine.list_operations()
        self.assertEqual([o['state'] for o in history],['unknown','done'])
        self.assertEqual(history[1]['retry_of'],'test-1')
        self.assertEqual(self.engine.audit()['reserved_fen'],24)
        self.assertEqual(self.engine.result('retry-1'),result)
        self.assertNotIn('base64',json.dumps(history))
        self.assertNotIn('prompt',json.dumps(history))

    def test_same_retry_delivery_is_cached_and_does_not_charge_again(self):
        self.first_failure();first=self.retry();second=self.retry()
        self.assertEqual(first,second)
        self.assertEqual(self.calls,2)

    def test_completed_or_missing_operation_cannot_be_retried(self):
        self.first_failure();self.retry()
        for previous in ('retry-1','missing'):
            with self.assertRaises(RequestError) as e:self.engine.retry({'request_id':previous,'retry_request_id':'next','confirm_new_charge':True})
            self.assertEqual(e.exception.code,'retry_not_available')

    def test_one_inflight_request_still_blocks_parallel_retry(self):
        self.first_failure()
        def delayed(*_):time.sleep(0.15);return payload()['image']
        self.engine._official=delayed
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            future=pool.submit(self.retry)
            deadline=time.monotonic()+1
            while not self.engine.audit()['inflight'] and time.monotonic()<deadline:time.sleep(0.005)
            with self.assertRaises(RequestError) as e:self.retry('retry-second-click')
            self.assertEqual(e.exception.code,'in_progress')
            future.result()
        self.assertEqual(self.engine.audit()['real_calls'],2)


class OfflineClient(LocalClient):
    def connect(self):raise ConnectionRefusedError()


class LauncherTests(unittest.TestCase):
    def test_startup_uses_fake_config_and_does_not_submit_generation(self):
        with tempfile.TemporaryDirectory() as temp:
            config=Path(temp)/'api_key.local.json'
            config.write_text(json.dumps({'api_key':FAKE}),encoding='utf-8')
            controller=Controller(temp,config=PrivateConfig(config),port=0,client=OfflineClient(0))
            try:
                with patch('urllib.request.OpenerDirector.open',side_effect=AssertionError('No upstream network')):
                    audit=controller.start()
                    self.assertEqual(audit['real_calls'],0)
                    self.assertEqual(controller.server.server_address[0],'127.0.0.1')
                    self.assertEqual(controller.start()['real_calls'],0)
                    self.assertEqual(controller.status()['protocol_revision'],2)
                    self.assertEqual(controller.operations(),[])
                    self.assertFalse((Path(temp)/'results').exists())
                self.assertNotIn(FAKE,json.dumps(audit))
            finally:controller.stop()

    def test_reuses_compatible_service_without_reading_config_or_starting_second(self):
        class Existing:
            session='fixture-session'
            def connect(self):return {'mode':'official','model_profile':'flash','real_calls':7}
        class NeverRead:
            def read_key(self):raise AssertionError('No key read when reusing')
        with tempfile.TemporaryDirectory() as temp:
            controller=Controller(temp,config=NeverRead(),client=Existing(),engine_factory=lambda **_:self.fail('No second engine'))
            self.assertEqual(controller.start()['real_calls'],7)
            self.assertIsNone(controller.server)

    def test_occupied_incompatible_port_does_not_read_config(self):
        class Existing:
            def connect(self):raise LauncherError('existing_service_incompatible')
        class NeverRead:
            def read_key(self):raise AssertionError('No key read')
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(LauncherError):Controller(temp,config=NeverRead(),client=Existing()).start()

    def test_missing_config_does_not_create_or_replace_anything(self):
        with tempfile.TemporaryDirectory() as temp:
            controller=Controller(temp,client=OfflineClient(0))
            with self.assertRaises(ConfigError):controller.start()
            self.assertEqual(list(Path(temp).iterdir()),[])

    def test_results_and_manual_retry_work_over_ephemeral_native_http(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'api_key.local.json';p.write_text(json.dumps({'api_key':FAKE}),encoding='utf-8')
            controller=Controller(temp,config=PrivateConfig(p),port=0,client=OfflineClient(0))
            try:
                controller.start()
                attempts=[]
                def upstream(*_):
                    attempts.append(1)
                    if len(attempts)==1:raise UpstreamFailure('network_timeout')
                    return payload()['image']
                controller.engine._official=upstream
                status,_=controller.client.request('POST','/v1/images/generate',payload())
                self.assertEqual(status,502)
                with self.assertRaises(LauncherError):controller.retry('test-1')
                status,_=controller.retry('test-1',confirmed=True)
                self.assertEqual(status,200)
                operation=controller.operations()[-1]
                path=controller.save_result(operation['request_id'])
                self.assertEqual(path.read_bytes(),base64.b64decode(payload()['image']['base64']))
                self.assertEqual(len(attempts),2)
                self.assertNotIn(FAKE,json.dumps(controller.operations()))
            finally:controller.stop()

    def test_single_instance_mutex_does_not_launch_duplicate(self):
        class Function:
            def __init__(self,result):self.result,self.calls=result,[]
            def __call__(self,*args):self.calls.append(args);return self.result
        class FakeAPI:
            CreateMutexW=Function(55)
            CloseHandle=Function(True)
        api=FakeAPI()
        with patch('ctypes.get_last_error',return_value=0):
            lock=SingleInstance(api);self.assertTrue(lock.acquire());lock.close()
        with patch('ctypes.get_last_error',return_value=183):
            lock=SingleInstance(api);self.assertFalse(lock.acquire())
        self.assertEqual(api.CreateMutexW.calls[0][2],SingleInstance.NAME)


if __name__=='__main__':unittest.main(verbosity=2)
