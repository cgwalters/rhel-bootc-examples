# Sealed composefs demo

This demo builds a CentOS Stream 10 bootc host image with a fully verified
boot chain and a sealed application container (httpd) that is
cryptographically verified at mount time using fs-verity signatures.

## What this proves

The host OS boots through a chain where each stage verifies the next:

```
  UEFI Secure Boot
       |
       v
  Signed UKI (systemd-boot → kernel+initramfs)
       |  cmdline contains composefs=<fsverity-digest>
       v
  composefs root filesystem (verified by digest)
       |
       v
  .fs-verity keyring (app-signing-cert loaded at boot)
       |
       v
  Sealed app container (crun mounts via composefs, kernel enforces signatures)
```

Secure Boot guarantees the UKI hasn't been tampered with. The UKI's
embedded kernel command line pins the composefs root image to an exact
fs-verity digest, so the OS image is immutable. Once booted, a systemd
service loads the composefs signing certificate into the kernel's
`.fs-verity` keyring. When crun mounts a sealed application container
through composefs, the kernel verifies every file's content against the
fs-verity signature that was created at build time with the corresponding
private key.

The result: an unbroken trust chain from firmware to application container,
with no runtime signature checking in userspace. The kernel does all
verification.

## Prerequisites

- podman (with heredoc syntax support, i.e. podman >= 4.7)
- openssl (for key generation)
- cfsctl (built from this repo or installed)
- bcvk (for local VM testing, from bootc-dev/bcvk)
- just (task runner)

For the GHA workflow, you also need repository secrets for the signing keys.

## Local workflow

Generate keys, build both images, seal the app, and boot:

```
just keygen
just build-host
just build-app
just seal-app
just boot
```

The `keygen` target creates Secure Boot keys (PK, KEK, db) and a composefs
signing keypair under `target/keys/`. The host build embeds the composefs
signing certificate and configures Secure Boot UKI signing. The app build
produces a plain httpd container. The `seal-app` step pulls the app image
into a cfsctl repo, seals it, and signs it with the composefs private key.
Finally `boot` launches a bcvk VM with the host image using Secure Boot.

Once the VM is running, the sealed app can be launched:

```
just test
```

This SSHs into the VM, verifies the composefs root is mounted, then runs
the sealed httpd container with podman (which delegates to crun, which
mounts the sealed composefs image with signature verification).

## GHA workflow

The `.github/workflows/build-sealed.yml` workflow automates this for CI.
It expects four repository secrets:

- `SECUREBOOT_DB_KEY` — PEM-encoded Secure Boot db signing key
- `SECUREBOOT_DB_CERT` — PEM-encoded Secure Boot db signing certificate
- `COMPOSEFS_SIGNING_KEY` — PEM-encoded composefs signing private key
- `COMPOSEFS_SIGNING_CERT` — PEM-encoded composefs signing certificate

The workflow builds the host image with these keys passed as podman
build secrets, then builds and seals the app image in a separate job.
An optional third job boots the image in a bcvk VM on a self-hosted
runner with libvirt.

## Key details

### Hash algorithm

This demo uses `fsverity-sha256-12` for broader filesystem compatibility.
For production use, `fsverity-sha512-12` is recommended for stronger
security guarantees.

### Host image (Containerfile.host)

Two-stage build following the composefs-rs UKI pattern:

1. `base` stage: installs packages, embeds the signing cert, adds dracut
   and systemd config for loading the cert into the kernel keyring at boot.

2. `kernel` stage: mounts the base image, computes the composefs fs-verity
   digest with cfsctl, bakes it into the kernel command line, then builds
   the UKI signed with the Secure Boot db key.

The final image is the base with `/boot` from the kernel stage.

### App image (Containerfile.app)

A minimal CentOS Stream 10 httpd container. Nothing composefs-specific
happens at build time — sealing is a post-build step.

### Sealing workflow

After the app image is built:

1. `cfsctl oci pull` imports it into a composefs repository
2. `cfsctl oci seal` creates a sealed manifest with embedded fs-verity digests
3. `cfsctl oci sign --cert ... --key ...` creates a PKCS#7 signature artifact

The sealed image can then be mounted with `cfsctl oci mount --require-signature`
or run via crun's composefs integration.

---

Assisted-by: OpenCode (Claude Opus 4)
