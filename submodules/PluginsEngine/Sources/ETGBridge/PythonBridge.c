#include "PythonBridge.h"
#include <stdlib.h>
#include <string.h>

/// Нативный CPython-модуль "_etg" — мост Python → Swift.
/// Python-плагины (через extera_compat) вызывают _etg.call(command, json),
/// Swift получает строки и возвращает JSON-строку ответа.

static ETGSwiftCallback g_callback = NULL;

void etg_set_swift_callback(ETGSwiftCallback cb) {
    g_callback = cb;
}

/// _etg.call(command: str, payload_json: str) -> str (json)
static PyObject *etg_call(PyObject *self, PyObject *args) {
    const char *command = NULL;
    const char *payload = NULL;
    if (!PyArg_ParseTuple(args, "ss", &command, &payload)) {
        return NULL;
    }
    if (g_callback == NULL) {
        PyErr_SetString(PyExc_RuntimeError, "_etg: swift callback not installed");
        return NULL;
    }
    char *result = g_callback(command, payload);
    if (result == NULL) {
        Py_RETURN_NONE;
    }
    PyObject *pyResult = PyUnicode_FromString(result);
    free(result);
    return pyResult;
}

static PyMethodDef ETGMethods[] = {
    {"call", etg_call, METH_VARARGS, "Call into the host app (JSON in, JSON out)."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef etgmodule = {
    PyModuleDef_HEAD_INIT,
    "_etg",
    "exteraGram-compat bridge into Telegram-ETG host.",
    -1,
    ETGMethods,
    NULL, NULL, NULL, NULL
};

static PyObject *PyInit__etg(void) {
    return PyModule_Create(&etgmodule);
}

int etg_register_module(void) {
    return PyImport_AppendInittab("_etg", &PyInit__etg);
}
