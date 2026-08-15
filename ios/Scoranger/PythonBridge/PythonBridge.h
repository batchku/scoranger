#ifndef PythonBridge_h
#define PythonBridge_h

/// Initialize the embedded interpreter. Call once, off the main thread.
/// resource_path: the app bundle's resource path (contains python/, app/, app_packages/)
/// Returns 0 on success, nonzero on failure.
int scoranger_python_init(const char *resource_path);

/// One JSON request in, one JSON response out (see PythonApp/app/bridge.py).
/// Caller must free() the returned string. Returns NULL only on catastrophic failure.
char *scoranger_python_call(const char *request_json);

#endif
