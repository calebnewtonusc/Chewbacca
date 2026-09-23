import copy
import datetime as dt
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from ux_decision import recommend,revalidate

class Decisions(unittest.TestCase):
 def setUp(self):
  self.now=dt.datetime(2026,9,23,tzinfo=dt.timezone.utc)
  self.map={'states':[{'id':'start','label':'Table'},{'id':'goal','label':'Column settings'}],'cost_unit':'relative_effort','edges':[
   {'id':'edit','from':'start','to':'goal','action':'Edit column','postcondition':'Settings visible','status':'observed','forbidden':False,'cost':1},
   {'id':'send','from':'start','to':'goal','action':'Send','postcondition':'Sent','status':'observed','forbidden':True,'cost':0}]}
  self.obs={'schema_version':1,'state_id':'start','observed_at':'2026-09-23T00:00:00Z','permitted_edges':['edit','send'],
   'controls':[{'id':'12','role':'button','name':'Edit column','enabled':True},{'id':'99','role':'button','name':'Send','enabled':True}],
   'bindings':[{'edge_id':'edit','control_id':'12'},{'edge_id':'send','control_id':'99'}]}
 def runrec(self,**kw):return recommend(self.map,'abc',self.obs,'goal',30,now=self.now,**kw)
 def test_exact_match_needs_no_model(self):
  def forbidden(*args,**kwargs):self.fail('model invoked for unique match')
  r=self.runrec(ask=forbidden);self.assertEqual(r['edge_id'],'edit');self.assertFalse(r['action_authorized'])
 def test_forbidden_cannot_be_permitted(self):
  self.obs['permitted_edges']=['send'];self.assertIsNone(self.runrec()['edge_id'])
 def test_disabled_excluded(self):
  self.obs['controls'][0]['enabled']=False;self.assertIsNone(self.runrec()['edge_id'])
 def test_documented_not_silently_promoted(self):
  self.map['edges'][0]['status']='documented';self.assertIsNone(self.runrec()['edge_id'])
 def test_fresh_revalidation(self):
  r=self.runrec();self.assertTrue(revalidate(self.map,'abc',self.obs,r,30,self.now)['current_binding_valid'])
 def test_observation_change_rejected(self):
  r=self.runrec();self.obs['controls'][0]['name']='Changed'
  with self.assertRaises(ValueError):revalidate(self.map,'abc',self.obs,r,30,self.now)
 def test_package_change_rejected(self):
  r=self.runrec()
  with self.assertRaises(ValueError):revalidate(self.map,'different',self.obs,r,30,self.now)
 def test_stale_and_future_rejected(self):
  for stamp in ['2026-09-22T23:59:00Z','2026-09-23T00:00:01Z']:
   self.obs['observed_at']=stamp
   with self.assertRaises(ValueError):self.runrec()
 def test_no_policy_for_ambiguous_actions_abstains(self):
  e=copy.deepcopy(self.map['edges'][0]);e['id']='alternative';self.map['edges'].append(e)
  self.obs['permitted_edges'].append('alternative');self.obs['bindings'].append({'edge_id':'alternative','control_id':'12'})
  self.assertIsNone(self.runrec()['edge_id'])
 def test_nan_budget_rejected(self):
  with self.assertRaises(ValueError):recommend(self.map,'abc',self.obs,'goal',float('nan'),now=self.now)
if __name__=='__main__':unittest.main()
