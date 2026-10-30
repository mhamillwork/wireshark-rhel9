# Release publishing

A development pipeline on a branch builds the RPM and publishes only the `-dev` image tags. It does not publish the release runtime image, the compile image, or the RPM.

A release publishes three things, in this order, from the `publish` job:

1. The runtime image, `artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9`
2. The compile image, `artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9-build`
3. The RPM, `https://artifactory.tahaa.local/artifactory/tahaa-rpm-local/wireshark-4.6.9-1.ppv1.0.5.el9.<arch>.rpm`

Those names come from `versions/RHEL9.env`. The image and the RPM use the same GitLab variables, `ARTIFACTORY_USERNAME` and `ARTIFACTORY_PASSWORD`.

The pipeline does not create the Git tag. You create it, protect it, and run the pipeline on that tag. `BUILD_TYPE` can stay `dev`. The tag is what selects the release publish.

## Before you tag

Set `ARTIFACTORY_USERNAME` and `ARTIFACTORY_PASSWORD` in the GitLab project under **Settings → CI/CD → Variables**. Leave them out of the repository. If the tag is protected, mark both variables **Protected** so the release pipeline can read them.

The `wireshark-docker` pod must be running in the `gitlab` namespace. The release pipeline builds the runtime image on that engine and the `publish` job pushes it from there.

## Create the tag

On the commit you want to release:

```bash
git tag 4.6.9-ppv1.0.5-rhel9
git push origin 4.6.9-ppv1.0.5-rhel9
```

With the versions in `versions/RHEL9.env` today, that name is `4.6.9-ppv1.0.5-rhel9`. After a version change, use `<WIRESHARK_VERSION>-ppv<PACKET_PENGUIN_VERSION>-rhel<RHEL_VERSION>`.

In GitLab, under **Settings → Repository → Protected tags**, protect a pattern that covers this tag. An unprotected tag does not set `CI_COMMIT_REF_PROTECTED`. The first job then stops, and the image and the RPM are not pushed.

## Run the pipeline on the tag

Pushing the tag starts a pipeline for that tag. That pipeline publishes the release runtime image, the compile image, and the RPM. `BUILD_TYPE` can stay `dev`. GitLab leaves it there, and the release tag still selects the release publish.

The tag has to be protected. If it is not, the first job stops with `release publish requires a protected Git ref` and nothing is pushed.

Start the release pipeline from the GitLab page for this project:

1. Open **Build → Pipelines**. On older GitLab this is **CI/CD → Pipelines**.
2. Click **New pipeline**.
3. Change the branch dropdown from `main` to the release tag `4.6.9-ppv1.0.5-rhel9`. The field is the ref the pipeline runs on. Leave it on `main` and the pipeline does not see the tag.
4. Leave `BUILD_TYPE` at `dev`, or select `release`. Either value publishes this tag.
5. Click **Start**. If the button is labeled **Run pipeline**, that is the same control.

A pipeline started on `main` does not see the tag, even when the tag points at the same commit. `CI_COMMIT_TAG` is set only when the pipeline ref is the tag. Selecting `release` while the dropdown still says `main` stops the publish with `release publish requires git tag 4.6.9-ppv1.0.5-rhel9`.

## What the publish job does

The earlier stages build and test first. The `rpm` stage writes the RPM. The `docker` stage builds the runtime image and checks `tshark` and `wireshark --version`. Those jobs do not log in to Artifactory.

The `publish` job then logs in and pushes the runtime image, then the compile image, then the RPM. The job log shows:

```text
Pushed artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9
Pushed artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9-build
Pushed RPM https://artifactory.tahaa.local/artifactory/tahaa-rpm-local/wireshark-4.6.9-1.ppv1.0.5.el9.<arch>.rpm
```

`-dev` image tags can stay in the repository. They are different tags and do not block the release.

## When the push stops

The release tags and the RPM are not replaced.

- If `wireshark:4.6.9-ppv1.0.5-rhel9` is already in Artifactory, the job stops there. The compile image and the RPM are not uploaded.
- If `wireshark:4.6.9-ppv1.0.5-rhel9-build` is already there, the runtime image may already have been pushed, and the job stops before the RPM.
- If `wireshark-4.6.9-1.ppv1.0.5.el9.<arch>.rpm` is already in `tahaa-rpm-local`, both images may already have been pushed, and the RPM upload stops.

Delete the existing release tag or RPM before running the release pipeline again. A log that only contains `Pushed ...-dev-...` is a development pipeline.

A pipeline on the wrong tag stops with `release publish requires git tag 4.6.9-ppv1.0.5-rhel9` when `BUILD_TYPE` is `release`. The first job reports that, before the image build.
