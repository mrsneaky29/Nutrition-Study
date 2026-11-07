"""Train and score research models of newly reported diagnoses in IHDS DS 3."""

import argparse
import json
from pathlib import Path
from zipfile import ZipFile

import numpy as np
import pandas as pd


DATA_MEMBER = 'ICPSR_37382/DS0003/37382-0003-Data.dta'
OUTCOMES = {'hypertension': 'MB5', 'diabetes': 'MB7', 'heart_disease': 'MB6'}
EDUCATION = ('none', 'primary', 'secondary', 'higher')
FEATURES = (
    'intercept', 'age_centered_scaled', 'age_centered_scaled_squared',
    'female', 'primary', 'secondary', 'higher', 'current_tobacco',
)
EXTRA_FEATURES = ('walk_difficulty', 'alcohol_use', 'worked',)
L2 = 0.0001
SEED = 37382


def load_panel(archive, expanded):
    columns = ['HHBASE', 'PBASE', 'XRO5', 'RO5', 'XRO3', 'XED6', 'XTO3_4', 'XTO5']
    columns += [prefix + code for code in OUTCOMES.values() for prefix in ('X', '')]
    if expanded:
        columns += ['XAD3', 'XTO6', 'XWKANY']
    with ZipFile(archive) as bundle, bundle.open(DATA_MEMBER) as source:
        with pd.read_stata(source, columns=columns, chunksize=15000,
                           convert_categoricals=False) as reader:
            panel = pd.concat(reader, ignore_index=True)
    if panel[['HHBASE', 'PBASE']].isna().any().any() or panel.duplicated(['HHBASE', 'PBASE']).any():
        raise ValueError('Expected one record per linked participant with household and person IDs.')
    return panel


def design(age, female, education, tobacco):
    scaled_age = (np.asarray(age, dtype=float) - 50) / 20
    education = np.asarray(education)
    return np.column_stack((
        np.ones_like(scaled_age), scaled_age, scaled_age**2, female,
        education == 'primary', education == 'secondary', education == 'higher', tobacco,
    ))


def sigmoid(logits):
    return np.exp(-np.logaddexp(0, -logits))


def fit(x, y):
    weights = np.zeros(x.shape[1])
    prevalence = y.mean()
    weights[0] = np.log(prevalence / (1 - prevalence))
    penalty = np.array([0.0] + [L2] * (x.shape[1] - 1))
    # The curvature of logistic loss is at most X.T @ X / (4n).
    curvature = x.T @ x / (4 * len(y)) + np.diag(penalty)
    learning_rate = 1 / np.linalg.eigvalsh(curvature)[-1]
    for step in range(50000):
        error = sigmoid(x @ weights) - y
        gradient = (x.T @ error) / len(y) + penalty * weights
        if np.max(np.abs(gradient)) < 1e-7:
            return weights, step, float(learning_rate)
        weights -= learning_rate * gradient
    raise RuntimeError('Gradient descent did not converge.')


def evaluate(y, logits):
    probabilities = sigmoid(logits)
    positives = int(y.sum())
    negatives = len(y) - positives
    ranks = pd.Series(probabilities).rank(method='average').to_numpy()
    auc = (ranks[y == 1].sum() - positives * (positives + 1) / 2) / (positives * negatives)
    return {
        'roc_auc': float(auc),
        'brier_score': float(np.mean((probabilities - y)**2)),
        'log_loss': float(np.mean(np.logaddexp(0, logits) - y * logits)),
        'mean_prediction': float(probabilities.mean()),
        'observed_rate': float(y.mean()),
    }


def train(archive, expanded=False):
    panel = load_panel(archive, expanded)
    adults = panel.loc[panel.XRO5.between(18, 120) & panel.RO5.notna()].copy()
    school = adults.XED6
    education = np.select(
        [school.isin([0, 55]), school.between(1, 5), school.between(6, 12), school.between(13, 16)],
        EDUCATION, default='unknown',
    )
    smoking, chewing = adults.XTO3_4, adults.XTO5
    current = smoking.isin([2, 3, 4]) | chewing.isin([2, 3, 4])
    tobacco_known = current | (smoking.eq(1) & chewing.eq(1))
    complete = adults.XRO3.isin([1, 2]) & (education != 'unknown') & tobacco_known
    x = design(adults.XRO5, adults.XRO3.eq(2), education, current)
    if expanded:
        complete &= adults.XAD3.isin([0, 1, 2]) & adults.XTO6.isin([1, 2, 3, 4])
        complete &= adults.XWKANY.isin([0, 1, 2, 3, 4])
        extra = (adults.XAD3.isin([1, 2]), adults.XTO6.isin([2, 3, 4]),
                 adults.XWKANY.isin([1, 2, 3, 4]))

    households = np.sort(adults.HHBASE.unique())
    rng = np.random.default_rng(SEED)
    test_households = rng.choice(households, size=round(0.2 * len(households)), replace=False)
    test = adults.HHBASE.isin(test_households)
    assert not set(adults.HHBASE[test]) & set(adults.HHBASE[~test])

    report = {
        'study': 'ICPSR 37382 V1 DS 3',
        'baseline': '2004-05',
        'follow_up': '2011-12',
        'endpoint': 'New household report of a doctor diagnosis, including reports coded cured',
        'features': FEATURES,
        'l2': L2,
        'household_split_seed': SEED,
        'panel_rows': len(panel),
        'adults_reinterviewed': len(adults),
        'adults_with_all_inputs': int(complete.sum()),
        'training_households': len(households) - len(test_households),
        'test_households': len(test_households),
        'outcomes': {},
    }
    for outcome, code in OUTCOMES.items():
        before, after = adults['X' + code], adults[code]
        eligible = complete & before.eq(0) & after.isin([0, 1, 2])
        features, inputs = FEATURES, x
        if expanded:
            other_conditions = {name: adults['X' + other_code] for name, other_code in OUTCOMES.items()
                                if name != outcome}
            for previous in other_conditions.values():
                eligible &= previous.isin([0, 1, 2])
            features += EXTRA_FEATURES + tuple('prior_' + name for name in other_conditions)
            inputs = np.column_stack((x, *extra, *(p.isin([1, 2]) for p in other_conditions.values())))
        y = after.isin([1, 2]).to_numpy(dtype=float)
        train_rows, test_rows = eligible & ~test, eligible & test
        y_train, y_test = y[train_rows], y[test_rows]
        weights, steps, learning_rate = fit(inputs[train_rows], y_train)
        logits = inputs[test_rows] @ weights
        base_rate = y_train.mean()
        baseline_logits = np.full(len(y_test), np.log(base_rate / (1 - base_rate)))
        probabilities = sigmoid(logits)
        risk_groups = np.array_split(np.argsort(probabilities, kind='stable'), 10)
        report['outcomes'][outcome] = {
            'weights': dict(zip(features, weights.tolist(), strict=True)),
            'gradient_steps': steps,
            'learning_rate': learning_rate,
            'training_n': len(y_train),
            'training_events': int(y_train.sum()),
            'test_n': len(y_test),
            'test_events': int(y_test.sum()),
            'test_model': evaluate(y_test, logits),
            'test_base_rate_model': evaluate(y_test, baseline_logits),
            'test_calibration_by_risk_tenth': [
                {'n': len(rows), 'predicted': float(probabilities[rows].mean()),
                 'observed': float(y_test[rows].mean())}
                for rows in risk_groups
            ],
        }
        if expanded:
            # Match the analysis sample so changes reflect the extra inputs.
            original_weights, _, _ = fit(x[train_rows], y_train)
            report['outcomes'][outcome]['test_four_input_model'] = evaluate(
                y_test, x[test_rows] @ original_weights,
            )
    if expanded:
        report['features'] = 'See per-outcome weights. Each model uses the other two diagnosis histories.'
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    training = commands.add_parser('train', help='Train and save weights and aggregate metrics.')
    training.add_argument('archive', type=Path)
    training.add_argument('output', type=Path)
    training.add_argument('--expanded', action='store_true', help='Add five IHDS inputs per outcome.')
    scoring = commands.add_parser('score-example', help='Score a synthetic research profile.')
    scoring.add_argument('model', type=Path)
    scoring.add_argument('--outcome', choices=OUTCOMES, required=True)
    scoring.add_argument('--age', type=int, choices=range(18, 106), metavar='18–105', required=True)
    scoring.add_argument('--sex', choices=['female', 'male'], required=True)
    scoring.add_argument('--education', choices=EDUCATION, required=True)
    scoring.add_argument('--current-tobacco', action=argparse.BooleanOptionalAction, required=True)
    for flag in ('walk-difficulty', 'alcohol-use', 'worked'):
        scoring.add_argument('--' + flag, action=argparse.BooleanOptionalAction)
    scoring.add_argument('--prior-diagnosis', choices=OUTCOMES, action='append', default=[],
                         help='Repeat for each other prior diagnosis. Omit if none were reported.')
    args = parser.parse_args()
    if args.command == 'train':
        result = train(args.archive, args.expanded)
        args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
        print(f'Wrote {args.output}')
        return

    report = json.loads(args.model.read_text(encoding='utf-8'))
    weights = report['outcomes'][args.outcome]['weights']
    x = design([args.age], [args.sex == 'female'], [args.education], [args.current_tobacco])
    features = FEATURES
    if 'walk_difficulty' in weights:
        if any(getattr(args, name) is None for name in EXTRA_FEATURES):
            scoring.error('Expanded models require explicit walk difficulty, alcohol use, and work inputs.')
        if args.outcome in args.prior_diagnosis:
            scoring.error('This model applies only without a previously reported diagnosis of the target condition.')
        other_conditions = [name for name in OUTCOMES if name != args.outcome]
        features += EXTRA_FEATURES + tuple('prior_' + name for name in other_conditions)
        extra = [getattr(args, name) for name in EXTRA_FEATURES]
        x = np.column_stack((x, [extra + [name in args.prior_diagnosis for name in other_conditions]]))
    probability = float(sigmoid(x @ np.array([weights[name] for name in features]))[0])
    print(json.dumps({'research_example_only': True, 'outcome': args.outcome,
                      'estimated_probability': probability}, indent=2))


if __name__ == '__main__':
    main()
