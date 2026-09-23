import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import clay_review as c

class Review(unittest.TestCase):
    def setUp(self):
        self.cols={'data':[{'id':n,'name':n} for n in c.REQUIRED]}
        values={n:'' for n in c.REQUIRED}
        values.update({'campaign':'Example','full_name':'Pat Example','send_status':'HOLD - research only',
          'Campaign Brief':'Record Found','Briefing Summary':'Company-owned brief version one.',
          'Investor Verification':'Response','Investor Outreach Draft':'Response','Use AI Status':'READY_FOR_DRAFT',
          'Use AI Review Status':'DRAFT_HOLD','Use AI Evidence Url':'https://example.org/team',
          'Use AI Source Url':'https://example.org/team; https://example.org/portfolio',
          'Use AI Email':'Example Fund lists Widget in its portfolio.','Use AI Subject':'Company introduction',
          'Draft QA Gate':'HUMAN_REVIEW_HOLD','Assembled Email - HOLD':'Hi Pat,\n\nExample Fund lists Widget in its portfolio.\n\nExample.\n\nAlex Example\nExample Company',
          'Assembled Follow-up - HOLD':'Hi Pat,\n\nFollowing up.\n\nAlex Example\nExample Company'})
        self.cells={k:{'status':'success','value':v} for k,v in values.items()}
        self.rows={'data':[{'id':'row1','cells':self.cells}]}
        self.manifest={'schema_version':1,'sender_signature':'Alex Example\nExample Company','template_signoff':'Alex','rows':[{'row_id':'row1','campaign':'Example','full_name':'Pat Example','first_touch_draft':'Hi [First name],\n\nExample.\n\nAlex','followup_draft':'Following up.','brief_sha256':c.digest_text(values['Briefing Summary'])}]}
    def verify(self):return c.verify(self.cols,self.rows,self.manifest)
    def test_candidate_is_always_held(self):
        r=self.verify();self.assertEqual(r['candidate_count'],1);self.assertFalse(r['send_authorized'])
    def test_stale_raw_copy_with_old_good_qa_is_excluded(self):
        self.cells['Investor Outreach Draft']['isStale']=True
        self.assertEqual(self.verify()['candidates'],[])
    def test_running_research_with_retained_ready_text_is_excluded(self):
        self.cells['Investor Verification']['status']='awaiting_callback'
        self.assertEqual(self.verify()['candidate_count'],0)
    def test_partial_url_rejected(self):
        self.cells['Use AI Evidence Url']['value']='https://example.org'
        self.assertEqual(self.verify()['candidate_count'],0)
    def test_changed_brief_requires_new_manifest(self):
        self.cells['Briefing Summary']['value']='Changed'
        self.assertIn('brief-version-mismatch',self.verify()['rows'][0]['reasons'])
    def test_blocked_with_cached_output_is_excluded(self):
        self.cells['Use AI Status']['value']='BLOCKED'
        self.assertEqual(self.verify()['candidates'],[])
    def test_campaign_mismatch(self):
        self.cells['campaign']['value']='Other'
        self.assertEqual(self.verify()['candidate_count'],0)
    def test_notheld_is_not_exported(self):
        self.cells['send_status']['value']='READY'
        self.assertEqual(self.verify()['candidates'],[])
    def test_missing_followup_not_complete_pair(self):
        self.cells['Assembled Follow-up - HOLD']['value']=''
        self.assertEqual(self.verify()['candidate_count'],0)
    def test_duplicate_ids_and_columns_rejected(self):
        self.rows['data'].append(copy.deepcopy(self.rows['data'][0]))
        with self.assertRaises(ValueError):self.verify()
        self.rows['data'].pop();self.cols['data'].append(self.cols['data'][0])
        with self.assertRaises(ValueError):self.verify()
    def test_six_rows_rejected(self):
        self.manifest['rows']*=6
        with self.assertRaises(ValueError):self.verify()
    def test_invalid_stale_flag_fails_closed(self):
        self.cells['Investor Verification']['isStale']='false'
        self.assertEqual(self.verify()['candidate_count'],0)
    def test_wrong_recipient_is_rejected(self):
        self.cells['full_name']['value']='Other Person'
        self.assertEqual(self.verify()['candidate_count'],0)
    def test_wrong_company_body_with_signature_rejected(self):
        self.cells['Assembled Email - HOLD']['value']='Hi Pat,\n\nWrong company.\n\nAlex Example\nExample Company'
        self.assertEqual(self.verify()['candidate_count'],0)
    def test_unrecognized_raw_response_shape_rejected(self):
        self.cells['Investor Outreach Draft']['value']={'review_status':'BLOCKED'}
        self.assertEqual(self.verify()['candidate_count'],0)
    def test_missing_sender_config_rejected(self):
        for key in ('sender_signature', 'template_signoff'):
            original = self.manifest.pop(key)
            with self.assertRaises(ValueError): self.verify()
            self.manifest[key] = original
    def test_signoff_and_signature_are_literal(self):
        self.manifest['template_signoff'] = 'A.*'
        self.manifest['rows'][0]['first_touch_draft'] = self.manifest['rows'][0]['first_touch_draft'].removesuffix('Alex') + 'A.*'
        self.manifest['sender_signature'] = r'Alex \1'
        for name in ('Assembled Email - HOLD', 'Assembled Follow-up - HOLD'):
            self.cells[name]['value'] = self.cells[name]['value'].replace('Alex Example\nExample Company', r'Alex \1')
        self.assertEqual(self.verify()['candidate_count'], 1)
    def test_fresh_process_replay(self):
        with tempfile.TemporaryDirectory() as d:
            paths=[]
            for name,value in [('columns',self.cols),('rows',self.rows),('manifest',self.manifest)]:
                p=Path(d)/f'{name}.json';p.write_text(json.dumps(value));paths.extend(['--'+name,str(p)])
            run=subprocess.run([sys.executable,str(Path(c.__file__).parent.parent/'bin/clay-review'),*paths],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stderr)
            self.assertEqual(json.loads(run.stdout)['candidate_count'],1)
if __name__=='__main__':unittest.main()
