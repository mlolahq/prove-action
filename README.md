# Mlola Prove

**Review the intent. Prove the result.**

This action proves that a pull request does what its approved change request
says. Each acceptance criterion is checked by your test report, your API or a
real browser, without a model. The result is a proof on the pull request: the
verdict for each criterion with its evidence, and the short list of things a
person still has to look at.

It runs [`mlola prove`](https://mlola.com/prove/docs/prove-a-change)
for every contract in the repository.

```yaml
- uses: mlolahq/prove-action@v1
  with:
    base-url: http://localhost:3000
```

## What you need

1. **A contract** for the change, in `contracts/`. A contract is the change
   request written so a machine can check it:
   [how to write one](https://mlola.com/prove/docs/prove-a-change#contract).
2. **Your tests as a JUnit report**, written before this step. Most runners
   can do it: Vitest `--reporter=junit`, Jest `jest-junit`, pytest
   `--junitxml`, Node `--test-reporter=junit`, Go `gotestsum --junitfile`.
3. **Your app running**, when a contract has API or browser criteria.

## A full workflow

Two jobs. `prove` runs your change: its tests, its app, and this action. It
holds no secrets. `seal` runs none of your change's code: it reads the
contracts, takes the proofs, checks each one again, signs it, and posts it.
`seal` is the check you require.

```yaml
name: prove
on: [pull_request]

permissions:
  contents: read

jobs:
  prove:                    # runs the change: no key here
    runs-on: ubuntu-latest  # Google Chrome is preinstalled
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }                            # the base branch, to compare with
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: npm ci
      - run: npm test -- --reporter=junit --outputFile=reports/junit.xml
      - name: Start the app
        run: |
          npm run start &
          npx -y wait-on@8 http://localhost:3000
      - uses: mlolahq/prove-action@v1
        continue-on-error: true                             # seal decides
        with:
          base-url: http://localhost:3000
          comment: false                                    # seal posts it

  seal:                     # runs none of the change's code: the key is only here
    needs: prove
    if: ${{ !cancelled() }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write  # for the proof comment
    env:
      MLOLA_RECEIPT_KEY: ${{ secrets.MLOLA_RECEIPT_KEY }}   # optional: signs the proofs
    steps:
      - uses: mlolahq/prove-action/seal@v1
```

The run then has:

- **A comment on the pull request** with each contract's proof, written from
  the proofs as `seal` checked them. Later runs update the same comment.
- **The same proof in the `seal` job's summary.**
- **An artifact, `mlola-proof`,** with the sealed proofs (`proof.json`) and
  their screenshots, for the audit trail.
- **A failed `seal` job** unless every contract has a sound proof that is
  proven. A contract with no proof, a proof of another contract or commit, or
  one edited after it was made fails it. Make `seal` a required check to gate
  the merge.

**Why two jobs.** The `prove` job runs your pull request's code and every
dependency it installs. A signing key in that job can be read by that code,
and used to sign anything, for any commit, later. In `seal` it cannot. What
this protects, and what it does not, is in
[the trust model](https://github.com/mlolahq/browser-runtime/blob/main/docs/trust-model.md).

**Quickest start.** The `prove` job alone, with `comment: true` and no key,
works too: the proofs are sealed by their digest only, and the job's own step
is the gate.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `contracts` | `contracts/*.json` | The contracts to prove: a glob, or several separated by spaces. |
| `base-url` | the contract's `baseUrl` | Where the API and browser checks run. |
| `base` | the pull request's base branch | The branch to compare with. It shows which files the change touched, and whether the contract is the approved one. |
| `approved` | | Contract digests approved elsewhere, such as a change-request system, separated by commas. |
| `baseline-dir` | | A directory of proofs made on the base branch (`<name>/proof.json`). Each criterion then shows its verdict before and after the change. |
| `storage-state` | | A browser storage state file, to start browser checks signed in. |
| `require-auto-merge` | `false` | Fail unless every contract is proven with nothing left for a person. |
| `comment` | `true` | Post the proof on the pull request. Set `false` when `seal` posts it. |
| `upload` | `true` | Keep the proofs as a workflow artifact. |
| `artifact-name` | `mlola-proof` | The name of that artifact. |
| `out` | `proof` | Where the proofs are written. |
| `version` | `0.19.0` | The `@mlola/browser-cli` version, exact. |
| `github-token` | the job's token | The token used to post the comment. |

## Outputs

| Output | Meaning |
| --- | --- |
| `verdict` | `proven`, `not-proven` or `not-proven-yet`: the worst over all contracts. |
| `auto-merge` | `true` when every contract is proven with nothing left for a person. |
| `proof-dir` | Where the proofs were written. |

`not-proven-yet` means a criterion could not be checked: no test report, the
app was not reachable, or a test was skipped.

## The seal action

`mlolahq/prove-action/seal@v1`, in a job after `prove`.

| Input | Default | Meaning |
| --- | --- | --- |
| `contracts` | `contracts/*.json` | The contracts that were proved: the same glob as `prove`. Each must have a proof. |
| `artifact-name` | `mlola-proof` | The artifact `prove` uploaded. |
| `out` | `proof` | Where `prove` wrote the proofs (its `out`). |
| `commit` | the run's commit | The commit the proofs must be about. |
| `require-auto-merge` | `false` | Fail unless every contract is proven with nothing left for a person. |
| `checkout` | `true` | Check out the repository for its contracts. Files are read; nothing is run. |
| `comment` | `true` | Post the proofs on the pull request. |
| `version` | `0.19.0` | The `@mlola/browser-cli` version, exact (0.19.0 or later). |
| `github-token` | the job's token | The token used to post the comment. |

| Output | Meaning |
| --- | --- |
| `verdict` | `proven`, `not-proven` or `not-proven-yet`, from the proofs as checked here. |
| `auto-merge` | `true` when every contract is proven with nothing left for a person. |
| `signed` | `true` when every proof was signed here. |
| `proof-dir` | Where the sealed proofs are. |

To merge by itself when nothing is left for a person, decide it in `seal`,
from the proofs it checked (give the job `contents: write` and
`pull-requests: write`):

```yaml
      - uses: mlolahq/prove-action/seal@v1
        id: seal
      - if: steps.seal.outputs.auto-merge == 'true'
        run: gh pr merge --auto --squash "${{ github.event.pull_request.number }}" --repo "${{ github.repository }}"
        env: { GH_TOKEN: "${{ github.token }}" }
```

## Signing

Without a key, a proof is sealed by a digest: it shows the proof was not
changed, not who made it. To sign it, create a key once
(`npx -p @mlola/browser-cli mlola receipt keygen`), store the private key as
the secret `MLOLA_RECEIPT_KEY`, and give it to the `seal` job only, as above.
Keep it in a GitHub environment with protection rules, and put `.github/`
under `CODEOWNERS`: a pull request carries its own workflow, and a proof of a
change that edits its CI goes to a person for that reason.

Anyone can then check a proof offline against the public key, and the commit
it must be about:

```bash
mlola receipt check proof/CR-123/proof.json --contract contracts/CR-123.json --trust ed25519:3f… --commit 4fedd54
```

**If your workflow gave the key to the job that runs the change** (the README
did before 1.4.0), move it to `seal`, and replace the key if pull requests
you did not write ran with it. The `prove` step warns while the key is there.

## Things to know

- **The contract is what a person reviews.** A contract that is new or changed
  in the pull request is listed for its approver, and auto-merge stays off. A
  `CODEOWNERS` entry for `contracts/` sends it to the right person.
- **A contract a model drafted is held.** `mlola contract draft`
  writes a first contract from a change request. Until a person approves it
  (it is merged to the base branch, or its digest is in `approved`), its API
  and browser checks do not run, and the verdict is `not-proven-yet`.
- **Checks act on the app you point them at.** API checks are GETs only and
  follow redirects only on the app's host, but a browser step can click a
  button that changes data. Use an app started in the
  job, or a preview environment with test data.
- **Pull requests from forks** get no secrets and a read-only token: their
  proofs are checked but stay unsigned, and the comment is skipped with a
  warning. The job summary and the artifact are still there.
- **Chrome** must be on the runner. GitHub's `ubuntu-latest` has it.

## License

MIT
