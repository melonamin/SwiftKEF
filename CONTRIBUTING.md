# Contributing to SwiftKEF

First off, thank you for considering contributing to SwiftKEF! It's people like you that make SwiftKEF such a great tool.

## Where do I go from here?

If you've noticed a bug or have a feature request, make sure to check our [Issues](https://github.com/yourusername/SwiftKEF/issues) page to see if someone else in the community has already created a ticket. If not, go ahead and [make one](https://github.com/yourusername/SwiftKEF/issues/new)!

## Fork & create a branch

If this is something you think you can fix, then [fork SwiftKEF](https://help.github.com/articles/fork-a-repo) and create a branch with a descriptive name.

A good branch name would be (where issue #325 is the ticket you're working on):

```bash
git checkout -b 325-add-japanese-localization
```

## Get the test suite running

Make sure you're using Swift 6.1+ and run:

```bash
swift test
```

## Implement your fix or feature

At this point, you're ready to make your changes! Feel free to ask for help; everyone is a beginner at first.

## Get the style right

Your patch should follow the same conventions & pass the same code quality checks as the rest of the project. We use:

- Swift standard naming conventions
- 4 spaces for indentation (no tabs)
- Comprehensive documentation comments for public APIs

## Make a Pull Request

At this point, you should switch back to your main branch and make sure it's up to date with SwiftKEF's main branch:

```bash
git remote add upstream git@github.com:yourusername/SwiftKEF.git
git checkout main
git pull upstream main
```

Then update your feature branch from your local copy of main, and push it!

```bash
git checkout 325-add-japanese-localization
git rebase main
git push --set-upstream origin 325-add-japanese-localization
```

Finally, go to GitHub and [make a Pull Request](https://help.github.com/articles/creating-a-pull-request).

## Keeping your Pull Request updated

If a maintainer asks you to "rebase" your PR, they're saying that a lot of code has changed, and that you need to update your branch so it's easier to merge.

## Code of Conduct

Please note that this project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project you agree to abide by its terms.

## Thank you!

SwiftKEF is a community effort. We encourage you to pitch in and join the team!