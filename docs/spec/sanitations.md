_Author_:  @DimuthuMadushan \
_Created_: 2026/09/24 \
_Updated_: 2026/10/30 \
_Edition_: Swan Lake

# Sanitation for OpenAPI specification

This document records the sanitation done on top of the official OpenAPI specification from Azure Data Lake. 
The OpenAPI specification is obtained from the [Azure Data Lake Storage 2019-10-31 specification](https://github.com/wso2/api-specs/blob/main/openapi/azure/datalake/2019-10-31/openapi.yml) (`openapi/azure/datalake/2019-10-31/` in `api-specs`), which is the upstream `DataLakeStorageClient` Swagger 2.0 document.
These changes are done in order to improve the overall usability, and as workarounds for some known language limitations.

1. **Added the Microsoft Entra ID OAuth 2.0 security schemes** (applied to `docs/spec/openapi.json`, before flatten and align)

   **Location**: top level — `securityDefinitions` and `security`

   **Original**: The specification declared no security scheme. The upstream document relies on AutoRest's host-side authentication, so the generated `ConnectionConfig` had no `auth` field.

   **Updated**: Added two OAuth 2.0 schemes against the Microsoft identity platform v2.0 endpoints, with `https://login.microsoftonline.com/common/oauth2/v2.0/token` as the token URL:
   - `azure_auth` — `accessCode` (authorization code) flow, authorization URL `https://login.microsoftonline.com/common/oauth2/v2.0/authorize`, scopes `https://storage.azure.com/user_impersonation` and `offline_access`, for delegated access with a refresh token.
   - `azure_auth_app` — `application` (client credentials) flow, scope `https://storage.azure.com/.default`, for app-only access.

   **Reason**: Data Lake Storage calls are authorized with a Microsoft Entra ID token issued for Azure Storage. An implicit flow has no token URL, so the generated `ConnectionConfig` could only take a bearer token that the caller has to renew. With these flows it carries `OAuth2ClientCredentialsGrantConfig|http:BearerTokenConfig|OAuth2RefreshTokenGrantConfig auth`, the same options as the Microsoft Teams connector, and the connector renews tokens itself. The generated `tokenUrl` and `refreshUrl` default to the `common` endpoint. The client credentials flow needs a tenant-specific endpoint, so callers override the default, as the README describes.

2. **Gave `x-ms-version` a default of `2019-10-31`** (applied to `docs/spec/openapi.json`, before flatten and align)

   **Location**: `parameters.Version` (the `x-ms-version` header, shared by all 12 operations)

   **Original**: An optional header with no default, described as "required when using shared key authorization".

   **Updated**: `default: "2019-10-31"` (converted to `schema.default`), and a description stating that the header is required for every authorized request, including those that use a bearer token.

   **Reason**: Azure Storage rejects Microsoft Entra ID requests that do not send `x-ms-version` 2017-11-09 or later. With the default, every generated `*Headers` record has `string xMsVersion = "2019-10-31"`, so the header is sent even when the caller passes no headers.

3. **Typed the append payload of `updatePath` as binary** (applied to `docs/spec/openapi.json`, before flatten and align)

   **Location**: `PATCH /{filesystem}/{path}` — the `in: body` parameter `requestBody` (consumes `application/octet-stream` and `text/plain`)

   **Original**: The body schema was `{"type": "object", "format": "file"}`, which the Swagger 2.0 to OpenAPI 3.0 conversion carries over as-is.

   **Updated**: `{"type": "string", "format": "binary"}`.

   **Reason**: The request body is the raw file data to append. The binary schema generates a `byte[] payload` parameter, which is what the previously published connector took.

4. **Narrowed the `readFile` response to `application/octet-stream`** (applied to `docs/spec/openapi.json`, before flatten and align)

   **Location**: `GET /{filesystem}/{path}` — the operation's `produces`

   **Original**: Three `produces` types (`application/json`, `application/octet-stream`, `text/plain`), each converted to a `string`/`binary` schema for the `200` and `206` responses (their schema is `type: file`).

   **Updated**: `produces: ["application/octet-stream"]` only, so the converted `200` and `206` content is `application/octet-stream` with the same `string`/`binary` schema.

   **Reason**: With three binary content types the generator returned `record {byte[] fileContent; string fileName;}`. The HTTP client cannot bind raw file bytes to that record, so every live read would fail. The service returns the file's own stored content type, whichever it is. The single binary content type generates `returns byte[]|error`, and binding to `byte[]` does not depend on the response content type.

5. **Added descriptions to undocumented schemas and fields** (applied to `docs/spec/openapi.json`, before flatten and align)

   **Location**: `definitions` — `Path`, `PathList`, `Filesystem`, `FilesystemList` and `DataLakeStorageError`, and every field of the first four

   **Original**: No `description`.

   **Updated**: Short descriptions, for example "The path of the file or directory, relative to the filesystem root" for `Path.name`. The inline `DataLakeStorageError.error` object was moved into its own definition, `DataLakeStorageErrorError` (renamed `DataLakeStorageErrorDetail` through `ai-mappings.json`), and the property now wraps it as `{"allOf": [{"$ref": "..."}], "description": "The service error response object"}`, because a bare `$ref` would lose its description. The conversion also adds a redundant `type: object` beside the `allOf`.

   **Reason**: The descriptions become the doc comments of the generated records. `DataLakeStorageError` is referenced only by the `default` error responses, which the client maps to `error`, so it is not generated into the package; its descriptions document the spec and the test mock.

## OpenAPI cli command

The following command was used to generate the Ballerina client from the OpenAPI specification. The command should be executed from the repository root directory.

```bash
bal openapi -i docs/spec/aligned_ballerina_openapi.json -o ballerina --mode client --client-methods remote --license docs/license.txt
```

Note: The license year is hardcoded to 2026, change if necessary.
