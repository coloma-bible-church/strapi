# Website

This is the source code for a future version of Coloma Bible Church's website.

The backend/API is powered by Strapi.

Everything is hosted in Azure.

# Development

* Install [Node.js](https://nodejs.org/en/download)
  * Pick the latest **LTS** version
* Install [VS Code](https://code.visualstudio.com/download)
  * Open this folder in VS Code and install the workspace-recommended extensions
* Install [Terraform](https://developer.hashicorp.com/terraform/install)
* Install dependencies
  ```
  yarn install
  ```
* Copy the `.env.example` file to a `.env` file
  * This creates a local copy of environment variables which are important for running Strapi locally. This `.env` file will not be placed in source control

# Strapi

Strapi is a headless content management system. It's the backend.

https://docs.strapi.io

## Edit content types

Run Strapi in developer mode to edit content types:

```
yarn develop
```

Edit your content types.

Then commit any code changes.

## Other Strapi features (using the CLI)

Strapi has a command line interface.

https://docs.strapi.io/dev-docs/cli

For example:

```
yarn run strapi generate
```

# Terraform

Terraform uses the `main.tf` file as the pattern for Azure Cloud resources.

https://developer.hashicorp.com/terraform

Run this command after making any changes to the providers used in `main.tf`:

```
terraform providers lock -platform=linux_arm64 -platform=linux_amd64 -platform=darwin_amd64 -platform=windows_amd64
```

# Deploy to Azure

The GitHub Actions pipeline files in this repository take care of automatically deploying stuff to Azure.

After deploying for the first time, make sure to manually set `CanNotDelete` locks on important resources (storage and database). That will help prevent you from accidentally deleting things in Azure (for example by accidentally removing an important section from `main.tf`).