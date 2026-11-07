# IHDS diagnosis prediction prototype

Three logistic regressions estimate the probability of a newly reported doctor diagnosis of hypertension, diabetes, or heart disease at the 2011–12 IHDS interview using 2004–05 answers. These are research models for reinterviewed adults in an older survey cohort. Their performance is an internal household holdout estimate. Use with a current Vivayu population would require independent validation.

## Run locally

From this directory, use Python 3.10 or newer with NumPy and pandas installed. Point the script at the original ICPSR Stata download.

```powershell
python model.py train "$env:USERPROFILE\Downloads\ICPSR_37382-V1.zip" results.json
python model.py score-example results.json --outcome hypertension --age 50 --sex female --education secondary --no-current-tobacco
```

The scoring command is for synthetic profiles with no reported baseline diagnosis of the selected condition. The JSON contains coefficients, aggregate holdout metrics, and average predictions versus observed rates for ten groups ordered by predicted risk.

The expanded models use the same household split and add five inputs per outcome. Their results also include a four-input model refitted on the same eligible participants for comparison.

```powershell
python model.py train "$env:USERPROFILE\Downloads\ICPSR_37382-V1.zip" expanded-results.json --expanded
python model.py score-example expanded-results.json --outcome diabetes --age 50 --sex female --education secondary --no-current-tobacco --no-walk-difficulty --no-alcohol-use --worked --prior-diagnosis hypertension
```

For a synthetic profile, pass `--prior-diagnosis` once per other previously reported diagnosis. Omit the flag for a profile with no other reported diagnoses.

## How the fields map

| Vivayu input | IHDS baseline field and encoding |
|---|---|
| Age | `XRO5`, centered at 50 and divided by 20. The model uses both this term and its square. |
| Sex | `XRO3`, female or male as coded in IHDS. |
| Education | `XED6`, grouped as no completed grade, grades 1–5, grades 6–12, or 13+ years. These are approximate mappings to Vivayu’s education categories. |
| Current tobacco use | `XTO3_4` and `XTO5`, positive for current smoking or chewing. Vivayu’s former and never categories both map to no current use. |

The expanded model adds these IHDS inputs:

| Input | Baseline field and encoding |
|---|---|
| Difficulty walking 1 km | `XAD3`, difficulty or inability versus no difficulty. |
| Alcohol use | `XTO6`, any use versus never. This survey item has no 30-day window. |
| Work activity | `XWKANY`, any farm, business, wage, or salaried work versus none. The IHDS measure excludes animal care. |
| Two other diagnoses | The two baseline `XMB5`, `XMB7`, or `XMB6` fields besides the outcome being modeled, with yes and cured coded as prior diagnosis. |

Each outcome uses a separate eligibility filter. The baseline diagnosis field must be `0` and the follow-up field must have a recorded `0`, `1`, or `2`. Follow-up `1` (cured) and `2` (yes) count as newly reported diagnoses because the question asks about ever being diagnosed. The three outcomes use `MB5`, `MB7`, and `MB6`, respectively, with `X` prefixed for baseline. Reports may come from another household member. An observed transition gives no exact diagnosis date and can include conditions that were already present but unreported at baseline.

The script assigns 20% of baseline households to testing using a fixed seed and trains on the rest. Full-batch gradient descent minimizes binary log loss plus an L2 penalty on the non-intercept weights. The comparison model predicts the training event rate for everyone. Results are unweighted and describe the eligible study sample.

[IHDS panel citation and documentation](https://doi.org/10.3886/ICPSR37382.v1) · [Follow-up questionnaire](https://ihds.umd.edu/sites/default/files/2022-08/ihds2ehq2.pdf)
