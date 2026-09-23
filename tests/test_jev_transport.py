import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'bin/lib'))
import jev
class Response:
 def __init__(self,value):self.value=value
 def __enter__(self):return self
 def __exit__(self,*a):pass
 def read(self):return json.dumps(self.value).encode()
class Transport(unittest.TestCase):
 def tearDown(self):jev._key=None
 def test_legacy_keychain_fallback_without_migration(self):
  jev._key=None
  with patch.dict(jev.os.environ,{'TYPESAFE_API_KEY':''}),patch.object(jev.subprocess,'run',side_effect=[SimpleNamespace(returncode=1,stdout=''),SimpleNamespace(returncode=0,stdout='synthetic-key')]) as runner:
   self.assertEqual(jev.api_key(),'synthetic-key');self.assertEqual(runner.call_count,2)
   self.assertIn('typesafe-ai',runner.call_args.args[0])
 def test_wrong_response_roots_abstain(self):
  for value in [[],None,17,'bad',{'answers':[]}]:
   with patch.object(jev,'allowed',return_value=True),patch.object(jev,'api_key',return_value='synthetic-key'),patch.object(jev.urllib.request,'urlopen',return_value=Response(value)):
    self.assertIsNone(jev.ask('synthetic',{}))
 def test_metadata_preserved_and_ask_compatible(self):
  payload={'answers':{'x':{'choice':'a'}},'model':'test-model','usage':{'input_tokens':1,'output_tokens':2},'private_diagnostic':'discard'}
  with patch.object(jev,'allowed',return_value=True),patch.object(jev,'api_key',return_value='synthetic-key'),patch.object(jev.urllib.request,'urlopen',return_value=Response(payload)):
   result=jev.ask_result('synthetic',{});self.assertNotIn('private_diagnostic',result)
   self.assertEqual(result['usage']['input_tokens'],1);self.assertEqual(jev.ask('synthetic',{}),payload['answers'])
 def test_no_consent_no_key_lookup(self):
  with patch.object(jev,'allowed',return_value=False),patch.object(jev,'api_key') as key:
   self.assertIsNone(jev.ask_result('synthetic',{}));key.assert_not_called()
 def test_choice_validation(self):
  valid={'choice':'a','probabilities':{'a':.8,'b':.2}}
  self.assertEqual(jev.validate_choice(valid,{'a','b'}),('a',.8))
  self.assertEqual(jev.validate_choice({**valid,'type':'choice'},{'a','b'}),('a',.8))
  self.assertIsNone(jev.validate_choice({**valid,'type':'noul'},{'a','b'}))
  for answer in [None,[],{'choice':[]}, {'choice':'a','probabilities':{'a':1}},
                 {'choice':'a','probabilities':{'a':.5,'b':.5}},
                 {'choice':'b','probabilities':{'a':.8,'b':.2}}]:
   self.assertIsNone(jev.validate_choice(answer,{'a','b'}))
  for value in [float('nan'),float('inf'),True,'1',-.1,1.1,10**400]:
   self.assertIsNone(jev.validate_choice({'choice':'a','probabilities':{'a':value,'b':0}}, {'a','b'}))
 def test_retry_policy_preserves_status_and_single_attempt_default(self):
  payload={'answers':{'x':{'choice':'a'}},'usage':{'input_tokens':2}}
  error=lambda code:jev.urllib.error.HTTPError('https://fixture.invalid',code,'fixture',{},None)
  with patch.object(jev,'allowed',return_value=True),patch.object(jev,'api_key',return_value='synthetic-key'),patch.object(jev.time,'sleep') as sleep:
   with patch.object(jev.urllib.request,'urlopen',side_effect=[error(503),Response(payload)]) as request:
    result=jev.ask_result('synthetic',{},max_attempts=4,retry_codes=(503,))
    self.assertEqual(result['attempts'],2);self.assertEqual(request.call_count,2);sleep.assert_called_once_with(1)
   with patch.object(jev.urllib.request,'urlopen',side_effect=[ValueError('invalid JSON'),Response(payload)]) as request:
    result=jev.ask_result('synthetic',{},max_attempts=4,retry_codes=(503,))
    self.assertEqual(result['attempts'],2);self.assertEqual(request.call_count,2)
   with patch.object(jev.urllib.request,'urlopen',side_effect=error(401)) as request:
    self.assertIsNone(jev.ask_result('synthetic',{},max_attempts=4,retry_codes=(503,)));self.assertEqual(request.call_count,1)
   with patch.object(jev.urllib.request,'urlopen',side_effect=error(503)) as request:
    self.assertIsNone(jev.ask_result('synthetic',{}));self.assertEqual(request.call_count,1)
if __name__=='__main__':unittest.main()
