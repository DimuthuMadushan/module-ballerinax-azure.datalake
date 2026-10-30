# Daily extract ingestion

This example lands a local data extract in Azure Data Lake Storage. It creates the target filesystem when it does not exist yet, creates a directory named after the extract date, uploads the file in chunks (append, then flush) to a temporary path, reads it back range by range to confirm that the stored content matches the local file, renames it into place, and lists the directory. A rerun for the same date replaces the earlier extract only after the new upload is verified. If the upload or the verification fails, the temporary file is removed.

## Prerequisites

### 1. Set up

Refer to the [setup guide](https://github.com/ballerina-platform/module-ballerinax-azure.datalake/tree/main/README.md#setup-guide) to create a storage account with a hierarchical namespace and obtain an access token.

### 2. Configuration

Create a `Config.toml` file in the example's root directory with the following values:

```toml
storageAccount = "<storage-account-name>"
token = "<access-token>"
filesystem = "<filesystem-name>"
extractDate = "<extract-date, for example 2026-09-24>"
localFilePath = "<path-to-local-file>"
chunkSize = 4194304
```

`chunkSize` is optional, must be greater than zero, and defaults to 4 MiB. Filesystem names must be 3 to 63 characters of lowercase letters, numbers and single dashes.

## Run the example

Execute the following command to run the example. The script will print its progress to the console.

```bash
bal run
```
