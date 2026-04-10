# Nothing by Eir

Static microsite for the "do nothing" ritual.

## Local preview

From the repository root:

```bash
python3 -m http.server 4173 --directory docs
```

Then open `http://localhost:4173/nothing/`.

## Deploying to GitHub Pages

This folder is self-contained and can be deployed in two ways:

1. Keep it in this repository and serve it as a subpath, such as `/nothing/`.
2. Publish the contents of this folder from a dedicated GitHub Pages repository if you want `nothing.eir.space` as its own custom domain.

GitHub Pages supports one Pages site per repository, and each Pages site has its own custom domain setting in repository Pages configuration:

- https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages
- https://docs.github.com/pages/configuring-a-custom-domain-for-your-github-pages-site/about-custom-domains-and-github-pages
