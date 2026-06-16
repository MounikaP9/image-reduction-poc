# OL9 Image Layering Demo Script

## Goal

Explain how a large Oracle Linux 9 image can be split into a reusable base layer and a smaller platform layer, so future package changes do not require moving the full 10GB image again.

Use this as a talk track while running the demo.

## 1. Opening

Say:

Today I am showing a proof of concept for reducing image transport overhead.

The starting point is a large Oracle Linux 9 image. In this demo, the image file is 10GB. Moving a file that large is slow, expensive, and painful when only a small part of the image changes.

The idea is simple: instead of treating the image as one big block, we split it into layers.

The base layer contains the stable operating system foundation. The platform layer contains tools and packages that change more often.

If a package is added or updated later, only the platform layer should change. The base layer should remain the same.

## 2. Explain The Picture

Say:

Think of the image like a building.

The base layer is the foundation: operating system base, kernel-related content, and stable system files.

The platform layer is what we put on top: tools, packages, application runtime files, and operational changes.

If we change a tool, we should not rebuild the foundation. We only replace the top layer.

## 3. Start Dashboard

Say:

I have a dashboard open so we can watch the process live. It shows which step is running, which steps passed, and how large each artifact is.

Run, if needed:

```bash
factory status
```

Point out:

- No step has run yet, or previous state has been reset.
- Validation is not complete yet.
- Artifact sizes may be zero until we build and split the image.

## 4. Step One: Build The Original Image

Run:

```bash
build
```

Say:

This step creates the original Oracle Linux image.

The image file has 10GB of capacity, but that does not mean it contains 10GB of useful data. It is like creating a 10GB empty box and then putting only the needed files inside it.

During this step, the system installs the base operating system packages first. Then it records that list as the frozen base baseline.

After that, it installs platform packages like Python, Podman, and Git. Those packages become the platform layer content.

Point out:

- We are not manually guessing every file.
- The script uses the image RPM database to understand which packages are base and which packages are platform.
- This makes the demo closer to a production process.

## 5. Step Two: Split The Image Into Layers

Run:

```bash
split
```

Say:

Now we split the original image into two compressed filesystem layers.

First, the system copies the image contents into a platform staging area.

Then it looks at the generated package manifest. Files that belong to frozen base packages are moved into the base layer. The remaining files stay in the platform layer.

At the end, both layers are compressed using SquashFS.

Point out:

- The base layer is reusable.
- The platform layer is expected to change more often.
- The split also records a list of base-owned files. That list is used later to make sure platform updates do not accidentally modify the base.

Explain the size reduction:

The original image is 10GB because it is a disk image with 10GB of capacity.

SquashFS stores actual files, not unused empty disk space. It also compresses the files.

That is why a 10GB image can turn into much smaller compressed layers, for example a small base layer and a larger platform layer.

If someone asks why the original is 10GB but the layers are under about 2GB, say:

The 10GB number is the size of the disk image container, not the amount of real data inside it.

Think of it like a 10GB suitcase. The suitcase can hold 10GB, but it may only contain 2GB of actual items. When we split and compress the image, we pack only the real files, not the empty space.

So the size drops for two reasons:

- Empty filesystem space is removed.
- Actual files are compressed by SquashFS.

The important clarification is that we are not magically compressing 10GB of active data down to 2GB. We are removing unused filesystem capacity and compressing the real content that exists inside the image.

## 6. Step Three: Deploy And Simulate A Day-2 Update

Run:

```bash
deploy
```

Say:

Now we mount the base layer and platform layer together using OverlayFS.

OverlayFS lets the system view multiple layers as one combined filesystem. To the user, it looks like one complete operating system image.

After the layers are combined, the demo simulates a Day-2 change. Day-2 means a change after the original image was already created.

In this demo, we add or update platform content. By default, the demo adds the package `jq` and updates a runtime config file.

The important part is this: the update is captured only as platform-layer change.

Point out:

- The script checks whether the update touched any frozen base-owned file.
- If it touches base-owned content, the update is rejected.
- If it only changes platform content, only the platform layer is rebuilt.
- The base layer checksum is checked before and after to prove it did not change.

Optional override:

```bash
DAY2_PLATFORM_PACKAGES="jq tmux" deploy
```

Say:

This is how we can demonstrate adding more platform tools without changing the base image.

## 7. Step Four: Validate The Result

Run:

```bash
validate
```

Say:

Validation proves that the layered result is correct.

The script mounts the original monolithic image again. Then it compares file checksums between the original image and the recomposed layered image.

It excludes only the intentional Day-2 platform changes, because we expect those files to be different.

Everything else should match.

Point out:

- The base layer digest is unchanged.
- The recomposed image matches the original outside the recorded platform delta.
- There is no unexpected data loss or corruption.

## 8. Show Logs Or Metrics

Run:

```bash
factory logs validate
```

Say:

This is the validation report. It shows that the base stayed stable and the platform delta was isolated.

Run:

```bash
factory metrics
```

Say:

These are the metrics used by Prometheus and Grafana. They show the same lifecycle status in machine-readable form.

## 9. Closing Summary

Say:

The key result is that we no longer need to transport the full 10GB image for every change.

We can keep the base layer stable and reusable.

When platform packages or tools change, we rebuild and transport only the platform layer.

This reduces transfer size, reduces update risk, and gives us a clear validation story:

- Base layer did not change.
- Platform layer captured the intended change.
- Final image still validates correctly.

That is the value of this layered image approach.

## 10. Simple One-Minute Version

Say:

We started with one large 10GB Oracle Linux image. Moving that full image every time is inefficient.

This demo splits the image into two parts: a stable base layer and a platform layer.

The base layer is like the foundation. The platform layer is where tools and packages live.

When we add or update a package, only the platform layer changes. The base layer stays the same.

We compress the layers with SquashFS, which removes empty disk space and compresses file content, so the transported artifacts are much smaller than the original 10GB disk image.

Finally, we validate the result by comparing checksums. That proves the layered image still matches the original, except for the platform changes we intentionally made.

## 11. Common Question: Why 10GB Becomes Less Than 2GB

Question:

Why is the original image 10GB, but the split layers are much smaller?

Short answer:

The 10GB image is a disk image with 10GB of capacity. It does not mean there are 10GB of real files inside it.

Longer answer:

When we create the image, we allocate a 10GB filesystem. That gives the image room to grow, but much of that space is empty.

SquashFS does not store the empty filesystem space. It stores the actual files and compresses them.

That is why the layers can be much smaller than the original image file.

Say:

This is similar to shipping the contents of a suitcase instead of shipping the suitcase plus all the empty air inside it.

The demo proves two things:

- We can remove unused disk-image space during transport.
- We can update only the platform layer instead of moving the full 10GB image again.
