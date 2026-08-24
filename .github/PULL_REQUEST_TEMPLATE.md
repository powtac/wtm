## Outcome

Describe the user-visible result and the capability boundary changed.

## Verification

- [ ] `./scripts/test`
- [ ] New behavior has automated coverage.
- [ ] UI changes were checked with VoiceOver, keyboard navigation, and increased text size.
- [ ] No credentials, signing identity, personal path, or proprietary model data is included.
- [ ] Documentation and `CHANGELOG.md` are updated when behavior changes.

## Risk

List filesystem, process, network, persistence, privacy, and migration effects. Write
`None` only after checking each category.

## Adapter checklist

- [ ] Not applicable, or the adapter contract and evidence hierarchy are documented.
- [ ] Fixtures are synthetic or redistributable and listed in `Fixtures/LICENSES.json`.
- [ ] Read-only discovery is isolated from storage actions and runtime execution.
