# Pass 2, chain bat: batch files in object storage

Brief: `work/tasks/P2-bat.md`. Decision: grilling outcome 7 (S3-compatible storage, MinIO in compose, retention 7 days
adjustable to 30, file size limit decided in the spec). Branch `ai/p2-bat`, module `api/batch-service`.

## B1: content in an S3-compatible bucket

### What changed

- `file` rows keep metadata only: id, organization, purpose, filename, size (`bytes`), `sha256`, `object_key`, expiry.
  Content is an object in one bucket, key `<organization>/<file id>`. Input files, output files and error files alike.
- `Bucket` (one class, AWS SDK v2 sync client; called `ObjectStore` until R2): `put(key, writer)`, `get(key)`, `download(key)`,
  `delete(key)`.
  Nothing is held whole in memory: `put` fills one 8 MiB buffer and sends it as a multipart part (a file that fits one
  part is a single PUT); `get` and `download` hand out the HTTP stream (`download` is the bounded one, see R2).
- Upload: the multipart part (spooled to disk by Tomcat) is streamed to the bucket, size and SHA-256 are taken while it
  goes. Download: streamed from the bucket to the client with the object's Content-Length.
- Batch creation is two passes. Pass 1 reads the input file from the bucket as a stream and validates line by line (same
  errors as before) with no database connection held; each valid line goes to a temp file. Pass 2 is one short transaction
  that inserts the batch row (its total is known) and the lines 1,000 at a time from the temp file. A bad line anywhere
  fails in pass 1 and creates nothing; the temp file is deleted in a `finally`.
- Output and error files are written from a cursor over the result lines (500 rows per fetch) into the bucket, then the
  file row is inserted. The file id derives from the batch id, so a retried finish overwrites the same object.
- Deleting a file (`DELETE /v1/files/{id}`), the hourly expiry sweep and the erasure of a closed organization all delete
  the object first and the row second. A failed object delete leaves the row, so the next call or sweep finds it again.
  (B2 builds the retention rules and its own tests on this.)
- The finisher no longer stops at the first batch that cannot finish: with the bucket down, every batch needs it, but one
  failure must not hide the others' state changes.

### Configuration (all environment, no defaults for secrets)

| Variable | Meaning |
|---|---|
| `STORAGE_ENDPOINT` | empty = AWS S3; `http://minio:9000` in compose (path-style addressing is used whenever it is set) |
| `STORAGE_REGION` | required; MinIO ignores it, the client insists on one |
| `STORAGE_BUCKET` | the bucket (must exist) |
| `STORAGE_ACCESS_KEY`, `STORAGE_SECRET_KEY` | static keys of a user that may use only that bucket |

`docker/compose.minio.yaml` is an overlay (`docker compose -f compose.yaml -f compose.minio.yaml up`): MinIO (digest
pinned, no published port, internal network), a one-shot `minio-init` that creates the bucket and a bucket-scoped user
(root credentials never reach batch), and the `batch` environment above. It takes everything from `.env` with `${VAR:?}`:
`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `STORAGE_BUCKET`, `STORAGE_ACCESS_KEY`, `STORAGE_SECRET_KEY`
(`STORAGE_REGION` defaults to `us-east-1`).

### Migration `V2026.10.08.001__object_storage.sql` (exact)

```sql
DELETE FROM file;
ALTER TABLE file
    DROP COLUMN content,
    ADD COLUMN sha256     CHAR(64)     NOT NULL,
    ADD COLUMN object_key VARCHAR(128) NOT NULL;
CREATE UNIQUE INDEX file_object_key ON file (object_key);
```

Clean cut-over, nothing copied: there is no production data, and a SQL migration cannot write to a bucket. Local test
files are dropped; batches that point at them keep their ids and answer 404 for those files (as if expired). Lines of
running batches live in `batch_line`, so those batches still finish and write their output into the bucket.

### Decisions and sources

**Client library: AWS SDK for Java v2 (`software.amazon.awssdk:s3` 2.55.12, sync client).**

- It is the reference S3 client, so it works against real S3 and against MinIO (path-style, custom endpoint). The MinIO
  Java SDK (`io.minio:minio` 9.0.3, still maintained: commits to 2026-09) is made for MinIO and pulls guava, okhttp (and
  with it Kotlin), BouncyCastle (`bcprov`, several MB; sizes of this closure not measured), commons-compress, snappy and Jackson 2 (its pom, Maven Central).
  The server MinIO is archived (below): tying the code to the MinIO SDK would tie it to that product; the S3 API outlives it.
- Weight measured on this module: 36 jars, 11.1 MB added to a classpath of 146 jars, 80.7 MB. The async client's Netty
  (`netty-nio-client`, a dozen jars) is excluded: this service is Spring MVC, not WebFlux (the brief assumed WebFlux;
  only the gateway is reactive), so a blocking client on the request thread is the natural fit, and the sync client
  streams request and response bodies. `apache5-client` (HttpClient 5) is the only synchronous HTTP client that `s3` brings, so it is the one in use, with
  explicit timeouts (2 s connect, 5 s pool, 30 s socket idle; per call see R2).
- Not used: S3 Transfer Manager / async multipart (needs the async client and Netty, or the CRT native library);
  Spring Cloud AWS (a layer over the same SDK for no gain here); Hadoop-style `s3a` (heavy).
- Checksums: since SDK 2.30.0 the SDK adds a CRC32 checksum on uploads by default
  ([AWS SDK for Java guide, "Data integrity protection with checksums"](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/s3-checksums.html)).
  Kept on. Multipart uploads name CRC32 in `CreateMultipartUpload` and echo each part's checksum in
  `CompleteMultipartUpload`; the S3 user guide says to always specify the algorithm at creation
  ([Checking object integrity for data uploads](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity-upload.html)).
  A service that predates trailing checksums can use the SDK's own switch `AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED`
  (discussion [aws-sdk-java-v2 #5802](https://github.com/aws/aws-sdk-java-v2/discussions/5802)).
  Tested against MinIO only; the multipart-with-checksum path on real AWS S3 follows the documents above and was not run.

**Store for compose and tests: MinIO `RELEASE.2025-09-07T16-13-09Z`, pinned by digest.**

- MinIO stopped publishing community images and binaries in October 2025, announced maintenance mode in December 2025, and
  archived the repository on 2026-04-25 ("THIS REPOSITORY IS NO LONGER MAINTAINED", github.com/minio/minio). This tag is
  the newest image I could confirm. It predates the source-only security release of 2025-10-15 and the fix for
  CVE-2025-62506 that the pgsty fork advertises, so it is for development and CI on the internal network only. Docker Hub's tag listing could not be fetched, so "last published" is
  not proven. If an image with fixes is wanted, the community fork `pgsty/minio` is a drop-in, or any other S3-compatible
  service: nothing in the code is MinIO-specific.
- Tests use `org.testcontainers:testcontainers-minio` (managed by Spring Boot's BOM, 2.0.5; class
  `org.testcontainers.containers.MinIOContainer`), same image, credentials made up per run.
- `minio/mc:RELEASE.2025-08-13T08-35-41Z` (digest pinned) creates the bucket and the scoped user in compose.

### Threat model for stored customer files

1. Who can read an object: only batch-service (its bucket-scoped key; MinIO root credentials stay with MinIO and its init job)
   and whoever holds the bucket's administrator. Object keys are `<organization>/<file id>`, and every read goes through
   a row looked up with the caller's organization first, so a guessed id from another organization answers 404.
2. No object is ever public and no signed URL is issued (out of scope); the bucket service has no published port in compose.
3. Deletion: the file row and its object are removed together, object first; a failed delete leaves the row and is retried
   by the next call or sweep (hourly for expiry, every minute for closed organizations). An object without a row is never
   served. It is avoided on ordinary failures: upload deletes its object when the row insert fails; the finisher deletes
   the files it wrote when its transaction rolls back (not when the commit itself failed, see R2); and a batch of a closed organization (erase) deletes its two
   deterministic output and error keys before it ends, so an object left by an earlier failed cleanup is removed (a
   failed delete rolls back and is retried). What is left is a crash between put and row insert, or a cleanup delete that
   fails because the bucket is down too; those wait for the B2 reconcile sweep and are bounded by such double failures,
   not by traffic.
4. Not logged: content, prompts, answers. Logs carry file ids, organization ids, exception class names (the SDK's messages
   name hosts and keys).
5. Not done here: encryption at rest (a property of the storage service or volume; production must enable server-side encryption and
   TLS to it), and LGPD erasure of object versions (the bucket must not have versioning on, or a delete only
   hides the object).

### Ceilings (also as `ponytail:` comments)

- 8 MiB of heap per upload in flight; a pooled buffer or smaller part when uploads run in the hundreds.
- Static keys from the environment; the default credential chain when hosting is decided.
- Orphan objects after a crash, or after a failed cleanup delete, wait for the B2 reconcile sweep; a failed multipart
  abort leaves parts until a lifecycle rule exists. A row insert that fails but did commit (connection lost during the
  commit) loses its object: the file then answers 404.
- A JSONL line is held whole while validated (a file without newlines is one line); B3's size limit bounds it.
- Batch creation holds no pooled connection while it reads the bucket (it stages to a temp file first). The temp file is as
  big as the input (B3's size limit) and the bucket read has no total deadline, only 30 s of silence per read: a slow
  bucket ties up request threads, not connections.
- The finisher holds one pooled connection per instance while it writes a batch's files (runs never overlap and batches
  finish one at a time); stage to a temp file after the transaction if a bucket outage must not tie it up.

## R2: fix-up of B1 (2026-10-08)

Review of B1 found five things; each is fixed with a test that fails on the B1 code (mutation runs below).

### What changed

1. **The 20 ITs were never run after the review fixes.** Run first, before any change, against a real MinIO and Postgres:
   `BatchServiceIT` 14 and `ObjectStoreIT` 6 green (plus 9 unit tests). After R2: 10 unit tests, `BatchServiceIT` 15 and
   `BucketIT` 10.
2. **The finisher never deletes after a failed finish** (`BatchFinisher.finish()`). B1 deleted the objects it had written when
   the transaction failed. R2 first kept them only when the failure came from the commit (outcome unknown). Review then
   showed the rollback branch was wrong too: the rollback has already released the batch's `FOR UPDATE SKIP LOCKED` row lock,
   so a second instance can lock the batch, write the same deterministic keys, commit the file rows, and then the first
   instance's cleanup deletes the second one's objects under committed rows (the paid output 404s for good). Now nothing is
   deleted on any failure: the next run finishes the batch again and overwrites the same keys (file id derives from the batch
   id), and a closed organization's erase path deletes those two keys. Objects of a batch that never finishes again wait for
   the B2 reconcile sweep. Test: `BatchFinisherTest` (rollback, commit failure and second-file failure all assert that no
   `delete` or `discard` is called).
3. **Slow readers could take the shared S3 pool.** A download streams from the S3 HTTP stream to the client and keeps its
   connection checked out until the client has read everything; 50 slow readers are the whole pool (default 50, acquisition
   timeout 5 s) and every upload, finisher put and erasure delete then fails for every tenant. Now:
   - `Bucket.download` takes a permit from a Resilience4j `Bulkhead` (`carmonai.batch.storage.max-downloads`, default 16,
     no wait): the 17th concurrent download answers `503 storage_busy` with `Retry-After: 1`, so at most 16 of the 50
     connections are ever held by clients. This service's own reads (`get`: batch creation, which is server-paced) take no permit.
   - A total deadline per download (`download-timeout`, default 15 min): the SDK's `apiCallTimeout` stops counting when the
     stream is handed out, and the socket timeout only sees silence, so a client that reads a little now and then would
     hold a connection for ever. After the deadline the next read aborts the connection and fails.
   - Closing a download before its end aborts the connection instead of draining the rest of the object; closing returns the
     permit exactly once.
   - Explicit SDK timeouts on every call: `attempt-timeout` 30 s (one HTTP attempt) and `call-timeout` 2 min (all attempts),
     next to the connect (2 s), pool (5 s) and socket (30 s) timeouts already set.
   - Retries only on idempotent calls: the SDK's default retries stay on for put, part upload, completion, get and delete;
     `CreateMultipartUpload` (a POST without an idempotency key: a repeat after a lost answer leaves a second, unreferenced
     upload) runs with the retry strategy switched off through a per-request `SdkPlugin`.
   - Tests: `BucketIT` (cap and recovery with 16 permits and 30 concurrent uploads while all are held; permit returned on
     end, early close and missing object; total deadline; a server that accepts and never answers: delete ends by its
     timeouts and was retried, create-upload is tried once) and `BatchServiceIT.downloadsThatAreBusyAnswer503AndDownloadsTheClientAbandonsReturnTheirPermit`
     (503 shape, then 40 downloads of a 24 MiB object that the client abandons after 1 KiB all get through, then a whole one).
4. **`ObjectStore` renamed `Bucket`** (the Insper `store` leftover check). `grep -rniw store` over `api/batch-service`
   (without `target/`) and `docker/compose.minio.yaml` returns nothing; the `mc` alias in the compose init job is now `local`.
5. **`docker/compose.minio.yaml`**: images were already `tag@sha256`; credentials already `${VAR:?}`. Now every container has a
   `user:`: `minio` and `minio-init` run as 10001, with `cap_drop: [ALL]`, `no-new-privileges`, and memory and CPU limits.
   A fresh named volume belongs to root and MinIO as a normal user fails with "file access denied" (checked), so a one-shot
   `minio-volume` runs `chown` as uid 0 with only `CAP_CHOWN`, a read-only filesystem and no network (see Deviations).
   Checked on the host: `config` refuses a missing `MINIO_ROOT_PASSWORD`; the stack came up (`minio` healthy, `minio-init`
   exit 0), the scoped user could write, read and delete in its bucket and was refused `mb other`; torn down with
   `down -v` on the project `carmonai-p2-bat` only.

### Configuration added (environment, defaults in `application.yaml`)

| Variable | Default | Meaning |
|---|---|---|
| `STORAGE_MAX_DOWNLOADS` | 16 | downloads streaming to clients at once (bulkhead) |
| `STORAGE_DOWNLOAD_TIMEOUT` | 15m | one download in total |
| `STORAGE_ATTEMPT_TIMEOUT` | 30s | one HTTP attempt of an S3 call |
| `STORAGE_CALL_TIMEOUT` | 2m | one S3 call with its retries |

### Mutation checks (each fails a named test; run with the new tests against the changed code, then restored)

| Mutation | Result |
|---|---|
| finisher discards after a failed finish (B1 behaviour; the rollback branch too) | `BatchFinisherTest.whenTheBatchCannotBeClosed...`, `...whenTheCommitFails...` and `...whenTheSecondFileFails...` fail |
| no download cap | `BucketIT.downloadsAreCapped...` fails: the 30 uploads hit "Timeout deadline: 5000 MILLISECONDS" on the exhausted pool (B1's failure) |
| permit never returned | 3 `BucketIT` and 2 `BatchServiceIT` tests fail (`Busy`) |
| no total deadline | `BucketIT.aDownloadThatTakesTooLongIsCutAndReturnsItsPermit` fails |
| create-upload retried again | `BucketIT.callsToABucketThatNeverAnswers...` fails |

### Deviations

- **Rule: container non-root (Hardening override 5).** `minio-volume` in `docker/compose.minio.yaml` runs as uid 0 for one
  `chown -R 10001:10001 /data` and exits. Reason: a fresh Docker named volume is owned by root, and MinIO as uid 10001
  cannot write it (reproduced). Mitigations: only `CAP_CHOWN`, read-only root filesystem, `network_mode: none`,
  `no-new-privileges`, no secrets in its environment. Alternatives rejected: a `tmpfs` volume with `uid=10001` (data lost whenever
  the container stops, while the file rows in Postgres stay, so downloads would 404); a bind mount (host paths and
  permissions differ per machine); leaving MinIO as root (breaks the rule outright). The orchestrator can accept this or
  ask for the tmpfs variant for CI only.
- **Rule: resilience (Hardening override 3), a bulkhead per dependency.** Downloads have one; uploads, finisher puts and
  deletes do not (their concurrency is bounded by Tomcat's threads and the pool of 50, and an exhausted pool answers 503
  `storage_unavailable` after the 5 s acquisition timeout). A write bulkhead and a metric for the permits are the next step if
  the scorecard shows upload pressure. No circuit breaker around the S3 client: the explicit timeouts and 503s are the only
  protection today.

### Lines a reviewer must read twice

- `Bucket.java`: `download`, `Download` (permit release exactly once on every path, abort versus close), the constructor's
  timeouts, `NO_RETRY`.
- `BatchFinisher.finish()`: the `bodyDone` flag and which branch deletes.
- `BatchResource.busy` and `BatchService.content` (the only place a client download is opened).

### Ceilings (also as `ponytail:` comments)

- The permit gauge/metric is not exported; Prometheus cannot yet alert on `storage_busy`.
- A download deadline is checked on each read, so one read can overshoot by up to the 30 s socket timeout.
- After a failed commit the objects stay: if the commit really failed and the batch is never finished again (its organization
  closes, which deletes the two keys; or the batch is dropped), an object could wait for the reconcile sweep of B2.
- `CompleteMultipartUpload` is retried by the SDK; if the first try succeeded and its answer was lost, the retry fails with
  `NoSuchUpload`, the upload fails, and the completed object stays without a row (an orphan for the B2 sweep).

### Built (paragraph for `inference-plan.md`, in the voice of its progress blocks)

**Pass 2, batch R2 built 2026-10-08** (fix-up of B1; log in [pass-2-bat-progress.md](pass-2-bat-progress.md)): batch-service keeps file content in an S3-compatible bucket through one class, `Bucket` (AWS SDK v2, Apache5 client, Postgres holds metadata only), MinIO digest-pinned in `docker/compose.minio.yaml` (every container has a `user:`; a one-shot root `chown` prepares the volume, a recorded deviation). Client downloads pass a bulkhead (16 at once, 503 `storage_busy` beyond) with a 15-minute total deadline, so slow readers cannot take the connection pool that uploads, finishes and erasure share; every S3 call has attempt and total timeouts and only idempotent calls retry. The finisher no longer deletes the objects of a batch whose commit outcome is unknown. Deviations, on purpose: the root `chown` container; no bulkhead or metric on the write side yet.
