# Upstream and local safety patch

Source: flutter_secure_storage_windows 4.2.2 from pub.dev, BSD-3-Clause.
Upstream: https://github.com/mogol/flutter_secure_storage

Original Dart backend SHA-256: `b3b07acd8398ef9ee73de40eb9e908404682ebec970b24d4caf884d77f87dc66`

The DPAPI cryptographic implementation and native C++ plugin behavior are unchanged; native source trailing whitespace was removed for the initial repository check. Local Dart changes preserve encrypted storage on read/format errors, remove backend diagnostics containing file paths or decoded data, validate the full decoded map, and replace encrypted storage through a flushed temporary file. Explicit delete/clear APIs remain available.

Windows native execution remains unverified until a Windows host is available. Root tests cover file-error policy and include a Windows-only corrupted-DPAPI regression. Do not drop this override until an upstream release meets these policies.
