#ifndef ETG_PYTHON_BRIDGE_H
#define ETG_PYTHON_BRIDGE_H

#include <Python.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Колбэк из Python в Swift. command — что делать ("call_event",
/// "send_message", "get_setting", ...), payloadJson — аргументы JSON-строкой.
/// Возвращает malloc'нутую JSON-строку с ответом (Swift освобождает через free).
typedef char *(*ETGSwiftCallback)(const char *command, const char *payloadJson);

/// Swift устанавливает колбэк ДО Py_Initialize.
void etg_set_swift_callback(ETGSwiftCallback cb);

/// Регистрация нативного модуля "_etg" — вызвать до Py_Initialize
/// (PyImport_AppendInittab("_etg", &etg_py_init)).
int etg_register_module(void);

#ifdef __cplusplus
}
#endif

#endif
