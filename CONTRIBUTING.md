# How to Contribute to Matter

Contributions to Matter are always welcome!

We welcome bug reports, suggestions, and code contributions. We want Matter to
be a project everyone feels they can use and be a part of.

## Code of Conduct

Matter and those participating in any of its spaces are governed by its [code of
conduct]. By participating you are also expected to uphold this code. Report any
unacceptable behavior to [lucas@lasttalon.dev].

[code of conduct]: CODE_OF_CONDUCT.md
[lucas@lasttalon.dev]: mailto:lucas@lasttalon.dev

## Reporting Bugs

If you found a bug, please let us know about it by submitting a GitHub [issue].

Be sure to:

- Check that an issue hasn't already been submitted about it. If you find one,
  please provide any additional information there.
- Provide a clear descriptive title and a detailed description of the problem
- Explain how and when the problem occurs and what steps to take to reproduce
  the problem

## Submitting Changes

### Did you write a patch that fixes a bug?

Thank you!

- Open a pull request against the `main` branch
- Clearly describe the problem and solution in the pull request
- Include any relevant [issue] number

### Did you intend to add a new feature or change an existing one?

Great!

- Create an [issue] suggesting the feature
  - We love when people contribute, but we hate for their effort to be wasted.
    Discussing the issue ahead of time can ensure the code you write will be
    accepted.
- Fork the project, and start writing
- When you're done, be sure to open a pull request against `main`
  - Include the issue number for the associated issue
  - Consider opening a draft pull request right away. This is the best way to
    discuss the code as you write it.

### Did you fix something purely cosmetic in the codebase?

We appreciate your enthusiasm, however cosmetic code patches are unlikely to be
approved. We do care about code quality, but the [cost] typically outweighs the
benefit of the change.

[cost]: https://github.com/rails/rails/pull/13771#issuecomment-32746700

## Releases

Releases for Matter are made by a maintainer using a release branch and a
pull request.

1. Create a new release branch
2. Update [`CHANGELOG.md`](CHANGELOG.md)
3. Bump the version in `wally.toml` according to [semver] guidelines
4. Create a pull request against `main`
5. Review to ensure a stable release
6. Make any necessary changes (be sure to keep `CHANGELOG.md` accurate)
7. Squash and merge the pull request
8. Push a new version tag
9. Write GitHub release notes

[semver]: https://semver.org/
[issue]: https://github.com/matter-ecs/matter/issues
