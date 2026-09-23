import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('decision_lab', ROOT / 'tools/decision_lab.py')
lab = importlib.util.module_from_spec(spec); spec.loader.exec_module(lab)


def registry():
    return {'schema_version': 1, 'id': 'visible-control', 'version': 'v1', 'model': lab.jev.MODEL,
            'question': 'Which visible control matches the supplied intent?',
            'criteria': {'save': 'Save configuration', 'cancel': 'Discard edits'},
            'mathematical': {'objective': 'Minimize incorrect recommendations', 'error_loss': 10,
                'abstain_loss': 1, 'confidence_threshold': 0.8,
                'budget': {'max_calls': 2, 'max_input_bytes': 1000, 'timeout_seconds': 2.5}},
            'creative': {'alternatives': ['exact text', 'semantic choice'], 'baseline': 'Exact text matching',
                         'falsifier': 'Jev has higher paired loss than exact text'},
            'proprietary': {'reusable_asset': 'Private verified outcomes', 'privacy': 'Explicit inputs only',
                            'ownership': 'User-owned records', 'novelty': 'adaptation'}}


def example():
    return {'id': 'case1', 'dataset_version': 'v1', 'provenance': 'Hand-created synthetic fixture',
            'config_version': 'v1', 'split': 'heldout', 'data_class': 'synthetic',
            'state': {'intent': 'save', 'visible': ['Save', 'Cancel']}, 'baseline': 'save'}


def answer(state, questions, timeout):
    return {'decision': {'choice': 'save', 'probabilities': {'save': .95, 'cancel': .05}}}


class DecisionLabTests(unittest.TestCase):
    def test_cost_threshold(self):
        self.assertAlmostEqual(lab.decision_threshold(registry()), .9)
        result = lab.decide(registry(), example(), ask=answer)
        self.assertEqual(result['choice'], 'save')
        self.assertFalse(result['action_authorized'])
        self.assertIsNone(result['actual_cost'])

    def test_low_confidence_abstains(self):
        response = lambda *a, **k: {'decision': {'choice': 'save', 'probabilities': {'save': .85, 'cancel': .15}}}
        self.assertEqual(lab.decide(registry(), example(), ask=response)['choice'], 'abstain')

    def test_malformed_distribution(self):
        for probs in ({'save': float('nan'), 'cancel': .1}, {'save': float('inf'), 'cancel': 0},
                      {'save': '0.9', 'cancel': .1}, {'save': True, 'cancel': 0}, {'save': .9},
                      {'save': .9, 'cancel': .9}, {'save': -.1, 'cancel': 1.1}):
            with self.subTest(probs=probs):
                response = lambda *a, **k: {'decision': {'choice': 'save', 'probabilities': probs}}
                self.assertEqual(lab.decide(registry(), example(), ask=response)['choice'], 'abstain')

    def test_failure_fallback(self):
        for response in (lambda *a, **k: None, lambda *a, **k: {'decision': []}):
            result = lab.decide(registry(), example(), ask=response)
            self.assertEqual(result['choice'], 'abstain')
            self.assertEqual(result['baseline'], 'save')
        with patch.object(lab.jev, 'ask_result', side_effect=TimeoutError):
            self.assertEqual(lab.decide(registry(), example(), live=True)['choice'], 'abstain')

    def test_stale_and_invalid_registry(self):
        state = example(); state['config_version'] = 'old'
        with self.assertRaises(ValueError): lab.decide(registry(), state)
        config = registry(); config['mathematical']['error_loss'] = float('nan')
        with self.assertRaises(ValueError): lab.validate_registry(config)
        config = registry(); config['proprietary']['novelty'] = 'unique'
        with self.assertRaises(ValueError): lab.validate_registry(config)

    def test_nonpublic_requires_optin_before_provider(self):
        state = example(); state['data_class'] = 'nonpublic'
        with patch.object(lab.jev, 'ask_result', side_effect=lambda *a, **k: {'answers': answer(*a, **k), 'model': 'resolved-v1', 'usage': {'input_tokens': 12, 'output_tokens': 3}}) as ask:
            with self.assertRaises(ValueError): lab.decide(registry(), state, live=True)
            ask.assert_not_called()
            result = lab.decide(registry(), state, live=True, allow_nonpublic=True)
            self.assertEqual(result['choice'], 'save')

    def test_model_drift_rejected(self):
        config = registry(); config['model'] = 'another-model'
        with patch.object(lab.jev, 'ask_result') as ask:
            with self.assertRaises(ValueError): lab.decide(config, example(), live=True)
            ask.assert_not_called()

    def test_private_ledger_idempotency_and_outcome_join(self):
        decision = lab.decide(registry(), example(), ask=answer)
        with tempfile.TemporaryDirectory() as directory:
            ledger = Path(directory) / 'private.jsonl'
            self.assertTrue(lab.append_record(ledger, decision))
            self.assertFalse(lab.append_record(ledger, decision))
            changed = {**decision, 'choice': 'cancel'}
            with self.assertRaises(ValueError): lab.append_record(ledger, changed)
            self.assertEqual(ledger.stat().st_mode & 0o777, 0o600)
            outcome = {'verified': True, 'label': 'save', 'verifier': 'test', 'evidence': str(Path(__file__).resolve()),
                       'evidence_sha256': lab.hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                       'input_hash': decision['input_hash'], 'config_hash': decision['config_hash']}
            lab.join_outcome(ledger, decision['id'], outcome)
            lab.join_outcome(ledger, decision['id'], outcome)
            with self.assertRaises(ValueError): lab.join_outcome(ledger, decision['id'], {**outcome, 'input_hash': 'stale'})
            report = lab.report(lab.read_records(ledger), registry())
            self.assertEqual(report['paired_count'], 1)
            self.assertFalse(report['promotion_allowed'])
            self.assertEqual(report['live_real_heldout_count'], 0)
            self.assertEqual(report['metrics']['jev']['mean_loss'], 0)
            self.assertIsNone(report['cost'])
            self.assertGreater(report['metrics']['jev']['conditional_error_wilson95'][1], .7)

    def test_training_not_evaluated(self):
        state = example(); state['split'] = 'train'
        decision = lab.decide(registry(), state, ask=answer)
        self.assertEqual(lab.report([decision], registry())['paired_count'], 0)

    def test_request_budget_includes_question(self):
        config = registry(); config['question'] = 'x' * 2000
        with patch.object(lab.jev, 'ask_result') as ask:
            with self.assertRaises(ValueError): lab.decide(config, example(), live=True)
            ask.assert_not_called()

    def test_invalid_registry_shapes(self):
        for config in ([], True, {'schema_version': True}, {**registry(), 'mathematical': []},
                       {**registry(), 'creative': []}, {**registry(), 'proprietary': []}):
            with self.subTest(config=config), self.assertRaises(ValueError):
                lab.validate_registry(config)

    def test_injected_provider_nonpublic_optin(self):
        state = example(); state['data_class'] = 'nonpublic'
        with self.assertRaises(ValueError): lab.decide(registry(), state, ask=answer)

    def test_training_leakage_excluded_and_evidence_digest_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = Path(directory) / 'ledger.jsonl'
            train = example(); train['split'] = 'train'
            decision = lab.decide(registry(), example(), ask=answer)
            lab.append_record(ledger, lab.decide(registry(), train, ask=answer))
            lab.append_record(ledger, decision)
            outcome = {'verified': True, 'label': 'save', 'verifier': 'test',
                       'evidence': str(Path(__file__).resolve()), 'evidence_sha256': 'wrong',
                       'input_hash': decision['input_hash'], 'config_hash': decision['config_hash']}
            with self.assertRaises(ValueError): lab.join_outcome(ledger, decision['id'], outcome)
            outcome['evidence_sha256'] = lab.hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
            lab.join_outcome(ledger, decision['id'], outcome)
            self.assertEqual(lab.report(lab.read_records(ledger), registry())['paired_count'], 0)

    def test_live_cli_preflight_budget_and_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            config = directory / 'registry.json'; config.write_text(json.dumps(registry()))
            cases = directory / 'cases.jsonl'; cases.write_text(json.dumps(example())+'\n')
            ledger = directory / 'ledger.jsonl'
            args = ['run', '--registry', str(config), '--examples', str(cases), '--ledger', str(ledger), '--live']
            with patch.object(lab.jev, 'ask_result', side_effect=lambda *a, **k: {'answers': answer(*a, **k), 'model': 'resolved-v1', 'usage': {'input_tokens': 12, 'output_tokens': 3}}) as ask, patch('builtins.print'):
                self.assertEqual(lab.main(args), 0)
                self.assertEqual(lab.main(args), 0)
                self.assertEqual(ask.call_count, 1)
                cases.write_text('\n'.join(json.dumps({**example(), 'id': str(i)}) for i in range(2)))
                self.assertEqual(lab.main(args), 2)
                self.assertEqual(ask.call_count, 1)

    def test_live_metadata_allowlist(self):
        with patch.object(lab.jev, 'ask_result', return_value={'answers': answer(None, None, None),
                'model': 'resolved-v1', 'usage': {'input_tokens': 12, 'output_tokens': 3,
                'total_tokens': float('nan'), 'private': 'must not retain'}}):
            result = lab.decide(registry(), example(), live=True)
            self.assertEqual(result['resolved_model'], 'resolved-v1')
            self.assertEqual(result['usage'], {'input_tokens': 12, 'output_tokens': 3})
            self.assertIsNone(result['actual_cost'])

    def test_report_rechecks_evidence_and_denominators(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = Path(directory) / 'ledger.jsonl'
            evidence = Path(directory) / 'evidence.txt'; evidence.write_text('verified source')
            first = lab.decide(registry(), example(), ask=answer)
            state = example(); state['id'] = 'case2'; state['state']['intent'] = 'discard'
            second = lab.decide(registry(), state, ask=lambda *a, **k: None)
            lab.append_record(ledger, first); lab.append_record(ledger, second)
            lab.join_outcome(ledger, first['id'], {'verified': True, 'label': 'save', 'verifier': 'test',
                'evidence': str(evidence), 'evidence_sha256': lab.hashlib.sha256(evidence.read_bytes()).hexdigest(),
                'input_hash': first['input_hash'], 'config_hash': first['config_hash']})
            result = lab.report(lab.read_records(ledger), registry())
            self.assertEqual(result['assigned_heldout_count'], 2)
            self.assertEqual(result['outcome_completion_rate'], .5)
            self.assertEqual(result['provider_failure_count'], 1)
            self.assertEqual(result['excluded_counts']['pending_outcome'], 1)
            self.assertFalse(result['evaluation_complete'])
            evidence.write_text('changed')
            result = lab.report(lab.read_records(ledger), registry())
            self.assertEqual(result['paired_count'], 0)
            self.assertEqual(result['excluded_counts']['missing_or_changed_evidence'], 1)
            evidence.unlink()
            self.assertEqual(lab.report(lab.read_records(ledger), registry())['paired_count'], 0)

    def test_report_mixed_modes_and_pending_assignments(self):
        first = lab.decide(registry(), example(), ask=answer)
        state = example(); state['state']['intent'] = 'discard'
        second = lab.decide(registry(), state)
        with self.assertRaises(ValueError): lab.report([first, second], registry())
        assignment = {**first, 'kind': 'assignment'}
        result = lab.report([assignment], registry())
        self.assertEqual(result['assigned_heldout_count'], 1)
        self.assertEqual(result['excluded_counts']['pending_decision'], 1)
        self.assertEqual(result['decision_completion_rate'], 0)

    def test_probability_floor_alias_compatibility(self):
        legacy = registry()
        modern = copy.deepcopy(legacy)
        modern['mathematical']['selected_probability_floor'] = modern['mathematical'].pop('confidence_threshold')
        for config in (legacy, modern):
            result = lab.decide(config, example(), ask=answer)
            self.assertEqual(result['choice'], 'save')
            self.assertAlmostEqual(result['effective_threshold'], .9)
        modern['mathematical']['confidence_threshold'] = .7
        with self.assertRaises(ValueError): lab.validate_registry(modern)
        modern['mathematical']['confidence_threshold'] = .8
        lab.validate_registry(modern)

    def test_asymmetric_loss_can_override_probability_argmax(self):
        config = registry(); config['mathematical']['confidence_threshold'] = 0
        config['mathematical']['loss_matrix'] = {
            'save': {'save': 0, 'cancel': 100},
            'cancel': {'save': 1, 'cancel': 0},
            'abstain': {'save': 2, 'cancel': 2}}
        result = lab.decide(config, example(), ask=answer)
        self.assertEqual(result['choice'], 'cancel')
        self.assertAlmostEqual(result['expected_losses']['save'], 5)
        self.assertAlmostEqual(result['expected_losses']['cancel'], .95)
        self.assertEqual(lab.realized_loss(config, 'save', 'cancel'), 100)
        self.assertEqual(result['reason'], 'minimum_expected_loss')
        self.assertFalse(result['action_authorized'])

    def test_loss_ties_and_dominating_abstain(self):
        config = registry(); config['mathematical']['confidence_threshold'] = 0
        config['mathematical']['loss_matrix'] = {
            'save': {'save': 1, 'cancel': 1},
            'cancel': {'save': 1, 'cancel': 1},
            'abstain': {'save': 2, 'cancel': 2}}
        self.assertEqual(lab.decide(config, example(), ask=answer)['reason'], 'risk_tied')
        config['mathematical']['loss_matrix']['abstain'] = {'save': .5, 'cancel': .5}
        result = lab.decide(config, example(), ask=answer)
        self.assertEqual(result['choice'], 'abstain')
        self.assertEqual(result['reason'], 'minimum_expected_loss_abstain')

    def test_invalid_loss_matrices(self):
        matrix = {'save': {'save': 0, 'cancel': 10}, 'cancel': {'save': 10, 'cancel': 0},
                  'abstain': {'save': 1, 'cancel': 1}}
        broken = [[], {'save': matrix['save']}, {**matrix, 'abstain': {'save': 1}}]
        for bad in (float('nan'), float('inf'), -1, True, '1'):
            candidate = copy.deepcopy(matrix); candidate['save']['cancel'] = bad; broken.append(candidate)
        for candidate in broken:
            config = registry(); config['mathematical']['loss_matrix'] = candidate
            with self.subTest(candidate=candidate), self.assertRaises(ValueError): lab.validate_registry(config)

    def test_huge_numbers_and_explicit_type_mismatch_abstain(self):
        config = registry(); config['mathematical']['error_loss'] = 10**400
        with self.assertRaises(ValueError): lab.validate_registry(config)
        for payload in ({'type': 'noul', 'choice': 'save', 'probabilities': {'save': .95, 'cancel': .05}},
                        {'choice': 'save', 'probabilities': {'save': 10**400, 'cancel': 0}}):
            self.assertEqual(lab.decide(registry(), example(), ask=lambda *a, **k: {'decision': payload})['choice'], 'abstain')
        payload = {'choice': 'save', 'probabilities': {'save': .95, 'cancel': .05}, 'confidence': 10**400}
        result = lab.decide(registry(), example(), ask=lambda *a, **k: {'decision': payload})
        self.assertEqual(result['choice'], 'save')
        self.assertIsNone(result['vendor_confidence'])

    def test_tied_probabilities_can_have_unique_matrix_minimum(self):
        config = registry(); config['mathematical']['confidence_threshold'] = 0
        config['mathematical']['loss_matrix'] = {'save': {'save': 0, 'cancel': 100},
            'cancel': {'save': 1, 'cancel': 0}, 'abstain': {'save': 2, 'cancel': 2}}
        response = lambda *a, **k: {'decision': {'choice': 'save', 'probabilities': {'save': .5, 'cancel': .5}}}
        result = lab.decide(config, example(), ask=response)
        self.assertEqual(result['choice'], 'cancel')
        self.assertEqual(result['expected_losses'], {'save': 50, 'cancel': .5, 'abstain': 2})

    def test_process_lock_refuses_concurrent_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            config = directory / 'registry.json'; config.write_text(json.dumps(registry()))
            cases = directory / 'cases.jsonl'; cases.write_text(json.dumps(example())+'\n')
            ledger = directory / 'ledger.jsonl'
            args = [str(ROOT / 'bin/decision-lab'), 'run', '--registry', str(config), '--examples', str(cases), '--ledger', str(ledger)]
            with lab.experiment_lock(ledger):
                blocked = subprocess.run(args, capture_output=True, text=True, timeout=10)
                self.assertEqual(blocked.returncode, 2)
                self.assertIn('already running', blocked.stderr)
                self.assertFalse(ledger.exists())
            allowed = subprocess.run(args, capture_output=True, text=True, timeout=10)
            self.assertEqual(allowed.returncode, 0, allowed.stderr)

    def test_pending_reservation_refuses_implicit_provider_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            config = directory / 'registry.json'; config.write_text(json.dumps(registry()))
            cases = directory / 'cases.jsonl'; cases.write_text(json.dumps(example())+'\n')
            ledger = directory / 'ledger.jsonl'
            args = ['run', '--registry', str(config), '--examples', str(cases), '--ledger', str(ledger), '--live']
            with patch.object(lab, 'decide', side_effect=RuntimeError('simulated interruption')), patch('builtins.print'):
                with self.assertRaises(RuntimeError): lab.main(args)
            self.assertEqual(lab.read_records(ledger)[0]['kind'], 'assignment')
            with patch.object(lab.jev, 'ask_result') as provider, patch('builtins.print'):
                self.assertEqual(lab.main(args), 2)
                provider.assert_not_called()

    def test_cli_fresh_process_offline_and_repeat(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            config = directory / 'registry.json'; config.write_text(json.dumps(registry()))
            cases = directory / 'cases.jsonl'; cases.write_text(json.dumps(example())+'\n')
            ledger = directory / 'ledger.jsonl'
            args = [str(ROOT / 'bin/decision-lab'), 'run', '--registry', str(config), '--examples', str(cases), '--ledger', str(ledger)]
            first = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            second = subprocess.run(args, capture_output=True, text=True)
            self.assertTrue(json.loads(second.stdout)[0]['reused'])
            self.assertEqual(len(lab.read_records(ledger)), 2)
            cases.write_text('\n'.join(json.dumps({**example(), 'id': str(i)}) for i in range(3)))
            rejected = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(rejected.returncode, 2)
            self.assertEqual(len(lab.read_records(ledger)), 2)

if __name__ == '__main__': unittest.main()
