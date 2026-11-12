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

```yaml
name: prove
on: [pull_request]

permissions:
  contents: read
  pull-requests: write      # for the proof comment

jobs:
  prove:
    runs-on: ubuntu-latest  # Google Chrome is preinstalled
    env:
      MLOLA_RECEIPT_KEY: ${{ secrets.MLOLA_RECEIPT_KEY }}   # optional: signs the proof
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
        with:
          base-url: http://localhost:3000
```

The job then has:

- **A comment on the pull request** with each contract's proof. Later runs
  update the same comment.
- **The same proof in the job summary.**
- **An artifact, `mlola-proof`,** with the proofs (`proof.json`) and their
  screenshots, for the audit trail.
- **A failed step** unless every contract is proven. Make the job a required
  check to gate the merge.

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
| `comment` | `true` | Post the proof on the pull request. |
| `upload` | `true` | Keep the proofs as a workflow artifact. |
| `artifact-name` | `mlola-proof` | The name of that artifact. |
| `out` | `proof` | Where the proofs are written. |
| `version` | `0.16.0` | The `@mlola/browser-cli` version, exact. |
| `github-token` | the job's token | The token used to post the comment. |

## Outputs

| Output | Meaning |
| --- | --- |
| `verdict` | `proven`, `not-proven` or `not-proven-yet`: the worst over all contracts. |
| `auto-merge` | `true` when every contract is proven with nothing left for a person. |
| `proof-dir` | Where the proofs were written. |

`not-proven-yet` means a criterion could not be checked: no test report, the
app was not reachable, or a test was skipped.

To merge by itself when nothing is left for a person:

```yaml
      - uses: mlolahq/prove-action@v1
        id: prove
        with: { base-url: http://localhost:3000 }
      - if: steps.prove.outputs.auto-merge == 'true'
        run: gh pr merge --auto --squash "${{ github.event.pull_request.number }}"
        env: { GH_TOKEN: "${{ github.token }}" }
```

## Signing

Without a key, a proof is sealed by a digest: it shows the proof was not
changed, not who made it. To sign it, create a key once
(`npx -p @mlola/browser-cli mlola receipt keygen`), store the private
key as the secret `MLOLA_RECEIPT_KEY`, and set it in the job's `env` as above.
Anyone can then check a proof offline against the public key:

```bash
mlola receipt check proof/CR-123/proof.json --contract contracts/CR-123.json --trust ed25519:3f…
```

## Things to know

- **The contract is what a person reviews.** A contract that is new or changed
  in the pull request is listed for its approver, and auto-merge stays off. A
  `CODEOWNERS` entry for `contracts/` sends it to the right person.
- **A contract a model drafted is held.** `mlola contract draft`
  writes a first contract from a change request. Until a person approves it
  (it is merged to the base branch, or its digest is in `approved`), its API
  and browser checks do not run, and the verdict is `not-proven-yet`.
- **Checks act on the app you point them at.** API checks are GETs only, but a
  browser step can click a button that changes data. Use an app started in the
  job, or a preview environment with test data.
- **Pull requests from forks** get a read-only token, so the comment is
  skipped with a warning. The job summary and the artifact are still there.
- **Chrome** must be on the runner. GitHub's `ubuntu-latest` has it.

## License

MIT
