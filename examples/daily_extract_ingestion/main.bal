// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

// Lands a local data extract in Azure Data Lake Storage. The example creates the target
// filesystem when it does not exist yet, creates a directory for the extract date, uploads
// the file in chunks (append, then flush) to a temporary path, reads it back range by range
// to confirm that the stored content matches the local file, renames it into place, and
// lists the directory. If the upload or the verification fails, the temporary file is removed.

import ballerina/http;
import ballerina/io;
import ballerina/url;
import ballerina/uuid;
import ballerinax/azure.datalake;

configurable string storageAccount = ?;
configurable string token = ?;
configurable string filesystem = ?;
configurable string extractDate = ?;
configurable string localFilePath = ?;
configurable int chunkSize = 4194304;

public function main() returns error? {
    if chunkSize <= 0 {
        return error(string `chunkSize must be greater than zero, got ${chunkSize}`);
    }
    datalake:Client datalake = check new ({auth: {token}}, string `https://${storageAccount}.dfs.core.windows.net`);

    // Step 1: Create the filesystem if it does not exist yet.
    // A HEAD request carries no error body, so a missing filesystem is reported by status code.
    http:Response properties = check datalake->getFilesystemProperties(filesystem, 'resource = "filesystem");
    if properties.statusCode == 404 {
        check datalake->createFilesystem(filesystem, 'resource = "filesystem");
        io:println(string `Created filesystem '${filesystem}'`);
    } else if properties.statusCode != 200 {
        return error(string `Could not read filesystem '${filesystem}': HTTP ${properties.statusCode}`);
    }

    // Step 2: Create a directory for this extract date. Missing parent directories are created with it.
    string directory = string `extracts/${extractDate}`;
    check datalake->createPath(filesystem, directory, 'resource = "directory");

    // Step 3: Upload the file to a temporary path, so a rerun leaves the existing extract in place
    // until the new one is verified. The per-run suffix keeps concurrent runs from sharing the path.
    string filePath = string `${directory}/${fileNameOf(localFilePath)}`;
    string tempPath = string `${filePath}.${uuid:createType4AsString()}.uploading`;
    check datalake->createPath(filesystem, tempPath, 'resource = "file");
    error? staged = uploadAndVerify(datalake, tempPath);
    if staged is error {
        // Remove the partial upload, but report the error that caused it.
        error? cleanup = datalake->deletePath(filesystem, tempPath);
        if cleanup is error {
            io:println(string `Could not remove ${filesystem}/${tempPath}: ${cleanup.message()}`);
        }
        return staged;
    }

    // Step 5: Rename the verified upload into place, replacing any earlier extract of the same name.
    check datalake->createPath(filesystem, filePath, {xMsRenameSource: string `/${filesystem}/${check encodePath(tempPath)}`});
    io:println(string `Stored ${filesystem}/${filePath}`);

    // Step 6: List what the directory now holds.
    datalake:PathList listing = check datalake->listPaths(filesystem, 'resource = "filesystem",
        recursive = false, directory = directory);
    foreach datalake:Path entry in listing.paths ?: [] {
        io:println(string `  ${entry.name ?: "<unnamed>"} (${entry.contentLength ?: 0} bytes)`);
    }
}

// Uploads the local file to tempPath and checks the stored content against it.
// Data is appended in chunks and becomes readable only once it is flushed.
function uploadAndVerify(datalake:Client datalake, string tempPath) returns error? {
    int position = 0;
    stream<io:Block, io:Error?> upload = check io:fileReadBlocksAsStream(localFilePath, chunkSize);
    check from io:Block block in upload
        do {
            check datalake->updatePath(filesystem, tempPath, block, action = "append", position = position);
            position += block.length();
        };
    check datalake->updatePath(filesystem, tempPath, [], action = "flush", position = position);
    io:println(string `Uploaded ${position} bytes to ${filesystem}/${tempPath}`);

    // Step 4: Verify the upload against the local file, one byte range per block.
    http:Response stat = check datalake->getPathProperties(filesystem, tempPath);
    if stat.statusCode != 200 {
        return error(string `Could not read ${tempPath}: HTTP ${stat.statusCode}`);
    }
    int storedLength = check int:fromString(check stat.getHeader("Content-Length"));
    if storedLength != position {
        return error(string `Stored length of ${tempPath} is ${storedLength} bytes, expected ${position}`);
    }
    int offset = 0;
    stream<io:Block, io:Error?> verify = check io:fileReadBlocksAsStream(localFilePath, chunkSize);
    check from io:Block block in verify
        do {
            string range = string `bytes=${offset}-${offset + block.length() - 1}`;
            byte[] stored = check datalake->readFile(filesystem, tempPath, {range});
            if stored != block {
                return error(string `Stored content of ${tempPath} does not match ${localFilePath} in ${range}`);
            }
            offset += block.length();
        };
    if offset != position {
        return error(string `${localFilePath} is ${offset} bytes now, but ${position} bytes were uploaded`);
    }
    io:println("Verified: the stored file matches the local extract");
}

// Percent-encodes each segment of a path for the x-ms-rename-source header, keeping the separators.
function encodePath(string path) returns string|error {
    string[] segments = [];
    foreach string segment in re `/`.split(path) {
        // url:encode uses form encoding, which turns a space into '+'; a path needs %20.
        segments.push(re `\+`.replaceAll(check url:encode(segment, "UTF-8"), "%20"));
    }
    return string:'join("/", ...segments);
}

function fileNameOf(string path) returns string {
    int? separator = path.lastIndexOf("/");
    return separator is int ? path.substring(separator + 1) : path;
}
