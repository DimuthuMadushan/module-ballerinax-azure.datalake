## Overview

[Azure Data Lake Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction) is Microsoft Azure's storage for big data analytics. It adds a hierarchical namespace to Azure Blob Storage, so that data is organized in filesystems, directories and files with POSIX-style permissions and access control lists, and can be used by Hadoop, Spark and other analytics workloads.

The Azure Data Lake connector lets Ballerina programs work with Data Lake Storage through its REST API, version 2019-10-31. It covers filesystems in a storage account, and the files and directories inside them: creating, renaming, listing and deleting paths, uploading and reading file content, managing properties and access control, and leasing files for exclusive access.

### Key features

- Create, list, configure and delete filesystems in a storage account
- Create, rename, list and delete files and directories in a hierarchical namespace
- Upload large files in chunks with append and flush, and read whole files or byte ranges
- Read and update path properties, owners, POSIX permissions and access control lists
- Acquire, renew, change, break and release leases for exclusive write access to a file

## Setup guide

To use the Azure Data Lake connector, you need a storage account with a hierarchical namespace, permission to use its data, and an application registered in Microsoft Entra ID.

### Step 1: Sign in to the Azure portal

1. Go to the [Azure portal](https://portal.azure.com/).
2. Sign in with an account that has an active subscription.

### Step 2: Create a storage account with hierarchical namespace

1. Search for **Storage accounts** and select **Create**.
2. Choose a subscription, resource group, region and a globally unique account name.
3. On the **Advanced** tab, select **Enable hierarchical namespace**.
4. Create the account.
5. Note the account's Data Lake endpoint, `https://<storage-account-name>.dfs.core.windows.net`. The connector sends every request to this URL.

### Step 3: Grant data-plane access

1. Open the storage account's **Access control (IAM)** page.
2. Assign one of the following roles to the user account that will sign in during Step 4:
    - **Storage Blob Data Contributor** to read and write data
    - **Storage Blob Data Owner** to also change owners, permissions and access control lists

### Step 4: Obtain a refresh token

The connector authenticates with an OAuth 2.0 refresh token from Microsoft Entra ID and renews its access token automatically.

> **Note:** For a walkthrough of the Microsoft Entra ID app registration with screenshots, see [Register an application in Microsoft Entra ID](https://central.ballerina.io/ballerinax/microsoft.teams/latest#step-1-register-an-application-in-microsoft-entra-id) in the Microsoft Teams connector setup guide. Add the Azure Storage permission below instead of the Microsoft Graph permissions it describes.

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com) and go to **Entra ID** > **App registrations** > **New registration**.
2. Enter a name, choose the supported account types, add `https://jwt.ms` as a **Web** redirect URI, and select **Register**.
3. On the application's **Overview** page, note the **Application (client) ID** and the **Directory (tenant) ID**.
4. Go to **Certificates & secrets** > **New client secret**, add a secret, and copy its **Value**. The value is shown only once.
5. Go to **API permissions** > **Add a permission** > **Azure Storage**, select the delegated **user_impersonation** permission, and select **Add permissions**. Grant admin consent if your tenant requires it.
6. Open the following URL in a browser, with your tenant ID and client ID, and sign in with the user account that has the role from Step 3:

    ```text
    https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize?client_id=<client-id>&response_type=code&redirect_uri=https%3A%2F%2Fjwt.ms&response_mode=query&scope=https%3A%2F%2Fstorage.azure.com%2Fuser_impersonation%20offline_access
    ```

7. Accept the consent prompt. The browser opens `https://jwt.ms/?code=<authorization-code>`. Copy the `code` value, which is single-use and expires within minutes.
8. Exchange the code for a refresh token:

    ```bash
    curl -X POST "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token" \
      --data-urlencode "client_id=<client-id>" \
      --data-urlencode "client_secret=<client-secret>" \
      --data-urlencode "scope=https://storage.azure.com/user_impersonation offline_access" \
      --data-urlencode "code=<authorization-code>" \
      --data-urlencode "redirect_uri=https://jwt.ms" \
      --data-urlencode "grant_type=authorization_code"
    ```

9. Copy the `refresh_token` value from the JSON response.

## Quickstart

To use the Azure Data Lake connector in your Ballerina application, update the `.bal` file as follows:

### Step 1: Import the module

Import the `azure.datalake` module.

```ballerina
import ballerinax/azure.datalake;
```

### Step 2: Instantiate a new connector

Create a `datalake:Client` with the storage account's Data Lake endpoint and the credentials from Step 4 of the setup guide.

```ballerina
configurable string storageAccount = ?;
configurable string tenantId = ?;
configurable string clientId = ?;
configurable string clientSecret = ?;
configurable string refreshToken = ?;

final datalake:Client datalake = check new ({
    auth: {
        clientId,
        clientSecret,
        refreshToken,
        refreshUrl: string `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`,
        scopes: ["https://storage.azure.com/user_impersonation", "offline_access"]
    }
}, string `https://${storageAccount}.dfs.core.windows.net`);
```

> **Note:** The connector's default token URL is the multi-tenant `https://login.microsoftonline.com/common/oauth2/v2.0/token` endpoint. It works only for applications that accept accounts from any organization, so change it to your tenant's endpoint, as `refreshUrl` does above.

Provide the values in a `Config.toml` file:

```toml
storageAccount = "<storage-account-name>"
tenantId = "<tenant-id>"
clientId = "<client-id>"
clientSecret = "<client-secret>"
refreshToken = "<refresh-token>"
```

### Step 3: Invoke the connector operation

List the filesystems in the storage account. Account-level operations take `'resource = "account"`.

```ballerina
public function main() returns error? {
    datalake:FilesystemList _ = check datalake->listFilesystems('resource = "account");
}
```

### Step 4: Run the Ballerina application

```bash
bal run
```

## Examples

The `Azure Data Lake` connector provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/module-ballerinax-azure.datalake/tree/main/examples/), covering the following use cases:

1. [Daily extract ingestion](https://github.com/ballerina-platform/module-ballerinax-azure.datalake/tree/main/examples/daily_extract_ingestion) - Upload a local extract into a dated directory in chunks, then list the directory and read the file back.
