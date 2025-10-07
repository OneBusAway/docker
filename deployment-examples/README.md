# Building and Deploying Immutable Docker Images

The simplest way to deploy a OneBusAway server to a compatible cloud provider (e.g. Render, Heroku) is by creating an immutable Docker image prebuilt with your transit agency's static GTFS data feed.

With a little hosting provider-specific automation, you should be able to automatically deploy the latest version of your image from the container registry to which you upload the image.

The Open Transit Software Foundation uses this approach with [OBACloud](https://onebusawaycloud.com), our OneBusAway as a Service offering, to build and deploy new containers in an easy, predictable, and horizontally scalable manner.

## Instructions

*All of the files referenced below can be found in the [immutable](./immutable) directory.*

### Setup and Image Building

1. Create a private repository on GitHub that will be the source for your images.
1. Copy `Dockerfile.mbta`, `docker-compose.yaml`, `bin`, and `config` into your repository.
1. Run `mkdir -p .github/workflows` in your repository and then copy `docker.yaml` to `.github/workflows/docker.yaml`
1. Test your new Docker image by running it with `docker compose up oba_app`
1. Assuming it builds successfully, access it at http://localhost:8080 and validate it using the `bin/validate.sh` script at the root of this repo.
1. Once you have successfully validated your image, commit your changes to GitHub and create a new Release of your repository.
1. The creation of the Release will kick off a new Action to build your Docker images. It will take 10-15 minutes to create the new images. Once it finishes, you'll be able to find them in your organization's Packages page.

### Update the Image

To update your image—for instance to force an update to the static GTFS feed, simply increment the `"REVISION"` value. You can automate this using `sed` or manually change the value. Then, create a new Release via the GitHub UI, command line, or API.
