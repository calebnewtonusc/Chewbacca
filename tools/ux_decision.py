#!/usr/bin/env python3
"""Bind a next-control recommendation to a fresh observation and a permitted graph edge."""
import argparse
import datetime as dt
import hashlib
import json
import sys
from decision_lab import decide, digest
from ux_learning import Invalid, package, read_json, require, route


def candidates(value, observation, goal, max_age_seconds, now=None):
    require(type(max_age_seconds) in (float, int) and 0 < max_age_seconds < float('inf'), 'invalid freshness budget')
    require(isinstance(observation, dict) and observation.get('schema_version') == 1, 'invalid observation')
    timestamp = observation.get('observed_at')
    require(isinstance(timestamp, str) and timestamp.endswith('Z'), 'observation must have UTC timestamp')
    observed = dt.datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
    require(observed.tzinfo is not None, 'timezone missing')
    now = now or dt.datetime.now(dt.timezone.utc)
    require(0 <= (now - observed).total_seconds() <= max_age_seconds, 'observation stale or future')
    states = {s['id'] for s in value['states']}
    require(observation.get('state_id') in states and goal in states, 'unknown state or goal')
    permitted = observation.get('permitted_edges')
    require(isinstance(permitted, list) and all(isinstance(x, str) for x in permitted), 'permitted edges required')
    edge_index = {e['id']: e for e in value['edges']}
    require(len(set(permitted)) == len(permitted) and set(permitted) <= edge_index.keys(), 'invalid permitted edges')
    controls, bindings = observation.get('controls'), observation.get('bindings')
    require(isinstance(controls, list) and isinstance(bindings, list), 'controls and bindings required')
    control_index = {}
    for c in controls:
        require(isinstance(c, dict) and set(c) == {'id','role','name','enabled'}, 'invalid control')
        require(all(isinstance(c[k], str) and c[k].strip() for k in ('id','role','name')), 'invalid control text')
        require(type(c['enabled']) is bool and c['id'] not in control_index, 'invalid or duplicate control')
        control_index[c['id']] = c
    eligible, seen = [], set()
    for b in bindings:
        require(isinstance(b, dict) and set(b) == {'edge_id','control_id'}, 'invalid binding')
        edge_id, control_id = b['edge_id'], b['control_id']
        require(isinstance(edge_id, str) and isinstance(control_id, str), 'invalid binding IDs')
        require(edge_id in edge_index and control_id in control_index and edge_id not in seen, 'unknown or duplicate binding')
        seen.add(edge_id)
        e, c = edge_index[edge_id], control_index[control_id]
        if edge_id not in permitted or e['forbidden'] or e['status'] != 'observed' or e['from'] != observation['state_id'] or not c['enabled']:
            continue
        remaining = route(value, e['to'], goal, excluded=[k for k in edge_index if k not in permitted])
        if remaining['reachable']:
            eligible.append({'edge_id':edge_id, 'control_id':control_id, 'role':c['role'], 'name':c['name'],
                             'action':e['action'], 'postcondition':e['postcondition'],
                             'estimated_route_cost':e['cost'] + remaining['estimated_cost']})
    return sorted(eligible, key=lambda c:(c['estimated_route_cost'], c['edge_id']))


def recommend(value, package_hash, observation, goal, max_age_seconds, registry=None,
              *, live=False, allow_nonpublic=False, ask=None, now=None):
    options = candidates(value, observation, goal, max_age_seconds, now)
    result = {'schema_version':1, 'package_sha256':package_hash, 'observation_sha256':digest(observation),
              'goal':goal, 'options':options, 'edge_id':None, 'control_id':None,
              'executed':False, 'action_authorized':False}
    if observation['state_id'] == goal:
        result['reason'] = 'already-at-goal'; return result
    if not options:
        result['reason'] = 'no-observed-permitted-route'; return result
    if len(options) == 1:
        result.update(edge_id=options[0]['edge_id'],control_id=options[0]['control_id'],reason='unique-code-match')
        return result
    if registry is None:
        result['reason'] = 'ambiguous-requires-review'; return result
    require(set(registry.get('criteria',{})) == {o['edge_id'] for o in options}, 'registry options must match eligible observed controls exactly')
    example = {'id':digest(observation), 'dataset_version':observation.get('dataset_version','1'),
               'provenance':'Explicit caller-supplied UI projection; not a full screenshot or live-state authentication.',
               'config_version':registry['version'], 'split':observation.get('split','train'),
               'data_class':observation.get('data_class','nonpublic'),
               'state':{'goal':next(s['label'] for s in value['states'] if s['id']==goal),
                        'current_state':next(s['label'] for s in value['states'] if s['id']==observation['state_id']),
                        'controls':options}, 'baseline':options[0]['edge_id']}
    decision = decide(registry,example,ask=ask,live=live,allow_nonpublic=allow_nonpublic)
    result['decision'] = decision
    chosen = next((o for o in options if o['edge_id']==decision['choice']),None)
    result['reason'] = decision['reason']
    if chosen:
        result.update(edge_id=chosen['edge_id'],control_id=chosen['control_id'])
    return result


def revalidate(value, package_hash, observation, recommendation, max_age_seconds, now=None):
    require(recommendation.get('package_sha256') == package_hash, 'package changed')
    require(recommendation.get('observation_sha256') == digest(observation), 'observation changed: decide again')
    options = candidates(value,observation,recommendation.get('goal'),max_age_seconds,now)
    matched = any(o['edge_id']==recommendation.get('edge_id') and o['control_id']==recommendation.get('control_id') for o in options)
    require(matched, 'no current eligible recommendation')
    return {'current_binding_valid':True, 'action_authorized':False, 'executed':False,
            'note':'Operator must verify the actual screen and task authority. This tool does not click.'}


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('package');p.add_argument('--observation',required=True);p.add_argument('--goal')
    p.add_argument('--max-age-seconds',type=float,required=True)
    p.add_argument('--registry');p.add_argument('--revalidate');p.add_argument('--live',action='store_true')
    p.add_argument('--allow-nonpublic',action='store_true')
    a=p.parse_args(argv)
    try:
        value,h=package(a.package);obs,_=read_json(a.observation)
        if a.revalidate:
            require(not a.live, 'revalidation cannot call a model')
            result=revalidate(value,h,obs,read_json(a.revalidate)[0],a.max_age_seconds)
        else:
            require(a.goal is not None,'goal required')
            result=recommend(value,h,obs,a.goal,a.max_age_seconds,read_json(a.registry)[0] if a.registry else None,
                             live=a.live,allow_nonpublic=a.allow_nonpublic)
        print(json.dumps(result,indent=2,allow_nan=False));return 0
    except (OSError,ValueError,TypeError,KeyError) as e:
        print(json.dumps({'error':str(e)}),file=sys.stderr);return 2

if __name__=='__main__':
    sys.exit(main())
