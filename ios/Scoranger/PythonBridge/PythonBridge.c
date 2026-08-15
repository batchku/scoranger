#include "PythonBridge.h"
#include <Python.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static PyObject *g_handle_fn = NULL;

static int add_path(PyConfig *config, const char *base, const char *suffix) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", base, suffix);
    wchar_t *wpath = Py_DecodeLocale(path, NULL);
    if (!wpath) return -1;
    PyStatus st = PyWideStringList_Append(&config->module_search_paths, wpath);
    PyMem_RawFree(wpath);
    return PyStatus_Exception(st) ? -1 : 0;
}

int scoranger_python_init(const char *resource_path) {
    if (g_handle_fn) return 0;

    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    if (PyStatus_Exception(Py_PreInitialize(&preconfig))) return 1;

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.buffered_stdio = 0;
    config.write_bytecode = 0;
    config.install_signal_handlers = 1;
    config.use_system_logger = 1;  // route stdout/stderr to the unified system log

    char home[1024];
    snprintf(home, sizeof(home), "%s/python", resource_path);
    wchar_t *whome = Py_DecodeLocale(home, NULL);
    PyConfig_SetString(&config, &config.home, whome);
    PyMem_RawFree(whome);

    config.module_search_paths_set = 1;
    if (add_path(&config, resource_path, "python/lib/python3.14")) return 2;
    if (add_path(&config, resource_path, "python/lib/python3.14/lib-dynload")) return 2;
    if (add_path(&config, resource_path, "app")) return 2;
    if (add_path(&config, resource_path, "app_packages")) return 2;

    PyStatus status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) return 3;

    PyObject *module = PyImport_ImportModule("bridge");
    if (!module) { PyErr_Print(); PyEval_SaveThread(); return 4; }
    g_handle_fn = PyObject_GetAttrString(module, "handle");
    Py_DECREF(module);
    if (!g_handle_fn || !PyCallable_Check(g_handle_fn)) { PyEval_SaveThread(); return 5; }

    PyEval_SaveThread();  // release the GIL; calls re-acquire per request
    return 0;
}

char *scoranger_python_call(const char *request_json) {
    if (!g_handle_fn) return NULL;
    PyGILState_STATE gil = PyGILState_Ensure();
    char *out = NULL;
    PyObject *result = PyObject_CallFunction(g_handle_fn, "s", request_json);
    if (result) {
        const char *utf8 = PyUnicode_AsUTF8(result);
        if (utf8) out = strdup(utf8);
        Py_DECREF(result);
    } else {
        PyErr_Print();
        out = strdup("{\"ok\": false, \"error\": \"python call failed (see console)\"}");
    }
    PyGILState_Release(gil);
    return out;
}
