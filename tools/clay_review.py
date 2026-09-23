#!/usr/bin/env python3
"""Replay a bounded Clay export review, excluding stale and unsupported draft states."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from ux_learning import Invalid, read_json, require

REQUIRED = ('campaign', 'full_name', 'send_status', 'Campaign Brief', 'Briefing Summary',
            'Investor Verification', 'Investor Outreach Draft', 'Use AI Status',
            'Use AI Review Status', 'Use AI Evidence Url', 'Use AI Source Url',
            'Use AI Email', 'Use AI Subject', 'Use AI Follow Up', 'Draft QA Gate',
            'Assembled Email - HOLD', 'Assembled Follow-up - HOLD')


def digest_text(value):
    return hashlib.sha256(value.encode()).hexdigest()


def index_columns(snapshot):
    require(isinstance(snapshot, dict) and isinstance(snapshot.get('data'), list), 'invalid columns snapshot')
    index = {}
    ids = set()
    for column in snapshot['data']:
        require(isinstance(column, dict), 'invalid column')
        name, identity = column.get('name'), column.get('id')
        require(isinstance(name, str) and isinstance(identity, str), 'invalid column identity')
        require(name not in index and identity not in ids, 'duplicate column name or ID')
        index[name] = identity
        ids.add(identity)
    require(set(REQUIRED) <= index.keys(), 'required workflow columns missing')
    return index


def verify(columns, rows, manifest):
    index = index_columns(columns)
    require(isinstance(rows, dict) and isinstance(rows.get('data'), list), 'invalid rows snapshot')
    require(isinstance(manifest, dict) and manifest.get('schema_version') == 1, 'invalid review manifest')
    for key in ('sender_signature', 'template_signoff'):
        require(isinstance(manifest.get(key), str) and manifest[key].strip(), 'missing ' + key)
        require(manifest[key] == manifest[key].strip(), 'unexpected surrounding whitespace: ' + key)
    signature = manifest['sender_signature']
    signoff_pattern = r'\s+' + re.escape(manifest['template_signoff']) + r'\s*$'
    selected = manifest.get('rows')
    # User's bounded test contract, not a learned performance threshold.
    require(isinstance(selected, list) and 1 <= len(selected) <= 5, 'select one to five rows')
    roster = {}
    for row in rows['data']:
        require(isinstance(row, dict) and isinstance(row.get('id'), str) and isinstance(row.get('cells'), dict), 'invalid row')
        require(row['id'] not in roster, 'duplicate source row ID')
        roster[row['id']] = row
    seen = set()
    results, candidates = [], []
    for item in selected:
        require(isinstance(item, dict) and set(item) == {'row_id', 'campaign', 'full_name', 'brief_sha256', 'first_touch_draft', 'followup_draft'}, 'invalid selected row')
        identity = item['row_id']
        require(isinstance(identity, str) and identity not in seen and identity in roster, 'duplicate or missing selected row')
        require(isinstance(item['campaign'], str) and item['campaign'].strip(), 'missing expected campaign')
        require(isinstance(item['brief_sha256'], str) and re.fullmatch('[a-f0-9]{64}', item['brief_sha256']), 'invalid expected brief digest')
        for key in ('full_name', 'first_touch_draft', 'followup_draft'):
            require(isinstance(item[key], str) and item[key].strip(), 'missing expected ' + key)
        require(re.match(r'^Hi[^,]*,\s*', item['first_touch_draft']) is not None and re.search(signoff_pattern, item['first_touch_draft']) is not None, 'unsupported first-touch template')
        seen.add(identity)
        cells = roster[identity]['cells']
        issues = []
        values = {}
        for name in REQUIRED:
            cell = cells.get(index[name])
            if not isinstance(cell, dict):
                issues.append('missing-cell:' + name)
                values[name] = None
                continue
            values[name] = cell.get('value')
            if cell.get('status') != 'success':
                issues.append('unfinished-cell:' + name)
            if 'isStale' in cell and type(cell['isStale']) is not bool:
                issues.append('invalid-staleness:' + name)
            elif cell.get('isStale'):
                issues.append('stale-cell:' + name)
        for raw_action in ('Campaign Brief', 'Investor Verification', 'Investor Outreach Draft'):
            if not isinstance(values[raw_action], str) or not values[raw_action].strip():
                issues.append('unsupported-raw-cell:' + raw_action)
        if values['full_name'] != item['full_name']:
            issues.append('recipient-mismatch')
        if values['send_status'] != 'HOLD - research only':
            issues.append('send-state-not-held')
        if values['campaign'] != item['campaign']:
            issues.append('campaign-mismatch')
        brief = values['Briefing Summary']
        if not isinstance(brief, str) or digest_text(brief) != item['brief_sha256']:
            issues.append('brief-version-mismatch')
        if values['Use AI Status'] != 'READY_FOR_DRAFT':
            issues.append('research-not-ready')
        if values['Use AI Review Status'] != 'DRAFT_HOLD':
            issues.append('draft-not-held')
        if values['Draft QA Gate'] != 'HUMAN_REVIEW_HOLD':
            issues.append('copy-qa-not-passed')
        for name in ('full_name', 'Use AI Subject', 'Use AI Email', 'Assembled Email - HOLD', 'Assembled Follow-up - HOLD'):
            if not isinstance(values[name], str) or not values[name].strip():
                issues.append('empty-text:' + name)
        evidence, sources = values['Use AI Evidence Url'], values['Use AI Source Url']
        urls = re.findall(r'https?://[^\s|;]+', sources) if isinstance(sources, str) else []
        if not isinstance(evidence, str) or evidence.strip() not in urls:
            issues.append('evidence-url-not-exact-member')
        opener = values['Use AI Email']
        if isinstance(opener, str) and len(opener.split()) > 25:
            issues.append('opener-over-limit')
        if values['Use AI Follow Up'] not in ('', None):
            issues.append('unexpected-generated-followup')
        for name in ('Assembled Email - HOLD', 'Assembled Follow-up - HOLD'):
            body = values[name]
            if isinstance(body, str) and body.strip():
                if '{{' in body or '}}' in body:
                    issues.append('unresolved-placeholder:' + name)
                if not body.rstrip().endswith(signature):
                    issues.append('sender-mismatch:' + name)
        if isinstance(opener, str):
            first_name = item['full_name'].strip().split()[0]
            expected_email = re.sub(r'^Hi[^,]*,\s*', lambda m: 'Hi ' + first_name + ',\n\n' + opener + '\n\n', item['first_touch_draft'])
            expected_email = re.sub(signoff_pattern, lambda m: '\n\n' + signature, expected_email)
            expected_followup = 'Hi ' + first_name + ',\n\n' + item['followup_draft'] + '\n\n' + signature
            if values['Assembled Email - HOLD'] != expected_email:
                issues.append('assembled-email-mismatch')
            if values['Assembled Follow-up - HOLD'] != expected_followup:
                issues.append('assembled-followup-mismatch')
        result = {'row_id': identity, 'campaign': item['campaign'], 'candidate_for_review': not issues,
                  'reasons': sorted(set(issues)), 'send_authorized': False}
        results.append(result)
        if not issues:
            candidates.append({'row_id': identity, 'campaign': item['campaign'], 'full_name': values['full_name'],
                               'subject': values['Use AI Subject'], 'email': values['Assembled Email - HOLD'],
                               'follow_up': values['Assembled Follow-up - HOLD'], 'evidence_url': evidence,
                               'send_status': 'HOLD - research only'})
    return {'schema_version': 1, 'selected_rows': len(selected), 'candidate_count': len(candidates),
            'rows': results, 'candidates': candidates, 'send_authorized': False,
            'scope': 'Snapshot consistency only; no source authentication, qualification or live freshness guarantee.'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--columns', required=True)
    parser.add_argument('--rows', required=True)
    parser.add_argument('--manifest', required=True)
    args = parser.parse_args(argv)
    try:
        inputs = [read_json(path) for path in (args.columns, args.rows, args.manifest)]
        result = verify(*(entry[0] for entry in inputs))
        result['input_sha256'] = {name: hashlib.sha256(entry[1]).hexdigest()
                                  for name, entry in zip(('columns', 'rows', 'manifest'), inputs)}
        print(json.dumps(result, indent=2, allow_nan=False))
        return 0
    except (OSError, ValueError, TypeError) as error:
        print(json.dumps({'error': str(error)}), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
